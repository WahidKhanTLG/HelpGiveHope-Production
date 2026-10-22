public with sharing class InHomeInterviewMobileController {

    private static final String SCHEDULE_OBJECT = 'Interview_Day_Schedule__c';
    private static final String DELIVERY_OBJECT = 'pmdm__ServiceDelivery__c';
    private static final String SERVICE_OBJECT = 'pmdm__Service__c';
    private static final String SYSTEM_ADMINISTRATOR_PROFILE = 'System Administrator';
    private static final String DELIVERY_NOTES_FIELD = 'Notes__c';
    private static final String OTHER_BED_NEEDS_FIELD = 'Other_Bed_Needs__c';
    private static final String CASE_RECOMMENDATION_FIELD = 'Home_Interview_Recommendation__c';
    private static final Integer PERSISTENCE_VERSION = 3;
    private static final String CHRISTMAS_COMPLETE_STATUS = 'Home Interview Complete';

    private static final Set<String> SECTION_KEYS = new Set<String>{
        'newBeds',
        'existingBedding',
        'linens',
        'smallAppliances',
        'furniture',
        'otherItems'
    };

    @TestVisible
    private static Boolean systemAdministratorOverride;

    @TestVisible
    private static Id currentUserIdOverride;

    @AuraEnabled
    public static List<Map<String, Object>> loadAssignedInterviews() {
        Id userId = currentUserId();
        Set<String> activeStatuses = new Set<String>{'Assigned', 'In Progress'};

        List<String> fields = new List<String>{
            'Id',
            'Case__c',
            'Booked__c',
            'Interview_Date__c',
            'Schedule_Mode__c',
            'Start_Time__c',
            'End_Time__c',
            'Assignment_Status__c',
            'Assigned_Volunteer__c',
            'Case__r.CaseNumber',
            'Case__r.Account.Name',
            'Case__r.Account.BillingStreet',
            'Case__r.Account.BillingCity',
            'Case__r.Account.BillingState',
            'Case__r.Account.BillingPostalCode'
        };

        if(fieldExists(SCHEDULE_OBJECT, 'Zone__c')) {
            fields.add('Zone__c');
            fields.add('Zone__r.Name');
        }
        if(fieldExists(SCHEDULE_OBJECT, 'Interview_Day__c')) {
            fields.add('Interview_Day__c');
            fields.add('Interview_Day__r.Zone__c');
            fields.add('Interview_Day__r.Zone__r.Name');
        }

        String queryText =
            'SELECT ' + String.join(fields, ',') +
            ' FROM Interview_Day_Schedule__c' +
            ' WHERE Assigned_Volunteer__c = :userId' +
            ' AND Booked__c = true' +
            ' AND Case__c != null' +
            ' AND Assignment_Status__c IN :activeStatuses' +
            ' ORDER BY Interview_Date__c ASC, Schedule_Mode__c ASC, Start_Time__c ASC' +
            ' LIMIT 250';

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for(SObject schedule : Database.query(queryText)) {
            SObject caseRecord = schedule.getSObject('Case__r');
            SObject accountRecord = caseRecord == null ? null : caseRecord.getSObject('Account');
            String status = stringValue(schedule.get('Assignment_Status__c'));

            results.add(new Map<String, Object>{
                'scheduleId' => schedule.get('Id'),
                'caseId' => schedule.get('Case__c'),
                'caseNumber' => caseRecord == null ? '' : stringValue(caseRecord.get('CaseNumber')),
                'householdName' => accountRecord == null ? '' : stringValue(accountRecord.get('Name')),
                'address' => buildAddress(accountRecord),
                'interviewDate' => schedule.get('Interview_Date__c'),
                'scheduleMode' => stringValue(schedule.get('Schedule_Mode__c')),
                'startTime' => schedule.get('Start_Time__c'),
                'endTime' => schedule.get('End_Time__c'),
                'zoneName' => resolveZoneName(schedule),
                'assignmentStatus' => status,
                'actionLabel' => status == 'In Progress' ? 'Resume' : 'Start Interview'
            });
        }

        return results;
    }

    @AuraEnabled
    public static Map<String, Object> loadInterview(Id recordId) {
        if(recordId == null) {
            throw new AuraHandledException('A Case or Interview Day Schedule record is required.');
        }

        Boolean systemAdministrator = isSystemAdministrator();
        Id caseId;
        Id scheduleId;

        if(recordId.getSObjectType() == Case.SObjectType) {
            caseId = recordId;
            scheduleId = findScheduleForCase(caseId);
            if(scheduleId == null) {
                return buildNotReadyResponse(
                    caseId,
                    'This Home Interview is read only until an interview is scheduled and a volunteer is assigned.'
                );
            }
        } else if(recordId.getSObjectType() == Interview_Day_Schedule__c.SObjectType) {
            scheduleId = recordId;
            SObject scheduleLink = Database.query(
                'SELECT Id, Case__c FROM Interview_Day_Schedule__c WHERE Id = :scheduleId LIMIT 1'
            );
            caseId = (Id)scheduleLink.get('Case__c');
        } else {
            throw new AuraHandledException('Open this component from a Case or Interview Day Schedule record.');
        }

        if(caseId == null) {
            throw new AuraHandledException('The selected interview schedule is not linked to a Case.');
        }

        SObject schedule = loadSchedule(scheduleId);
        if((Boolean)schedule.get('Booked__c') != true) {
            return buildNotReadyResponse(
                caseId,
                'This Home Interview is read only until the interview is scheduled and a volunteer is assigned.'
            );
        }

        SObject caseRecord = loadCase(caseId);
        SObject accountRecord = loadAccount((Id)caseRecord.get('AccountId'));
        List<Map<String, Object>> items = loadServiceDeliveries(caseId, scheduleId);
        Boolean canEdit = canEditInterview(schedule, systemAdministrator);
        Boolean readOnly = !canEdit || isLifecycleReadOnly(schedule);

        Map<String, Object> result = new Map<String, Object>();
        result.put('caseId', caseId);
        result.put('scheduleId', scheduleId);
        result.put('caseNumber', stringValue(caseRecord.get('CaseNumber')));
        result.put('householdName', accountRecord == null ? '' : stringValue(accountRecord.get('Name')));
        result.put('address', buildAddress(accountRecord));
        result.put('interviewDate', schedule.get('Interview_Date__c'));
        result.put('scheduleMode', stringValue(schedule.get('Schedule_Mode__c')));
        result.put('startTime', schedule.get('Start_Time__c'));
        result.put('endTime', schedule.get('End_Time__c'));
        result.put('zoneName', resolveZoneName(schedule));
        result.put('interviewerName', relationshipName(schedule, 'Assigned_Volunteer__r'));
        result.put('intervieweeName', relationshipName(caseRecord, 'Contact'));
        result.put('intervieweePhone', relationshipField(caseRecord, 'Contact', 'Phone'));
        result.put('contactPhone', stringValue(caseRecord.get('ContactPhone')));
        result.put('contactEmail', stringValue(caseRecord.get('ContactEmail')));
        result.put('assignmentStatus', stringValue(schedule.get('Assignment_Status__c')));
        result.put('whyHelp', fieldValue(caseRecord, 'Why_Help__c'));
        result.put('whyNotHelp', fieldValue(caseRecord, 'Why_Not_Help__c'));
        result.put('whyHelpFieldAvailable', fieldExists('Case', 'Why_Help__c'));
        result.put('whyNotHelpFieldAvailable', fieldExists('Case', 'Why_Not_Help__c'));
        result.put('santaInterest', booleanValue(fieldValue(caseRecord, 'Interested_in_Santa_Gifts__c')));
        result.put('santaFieldAvailable', fieldExists('Case', 'Interested_in_Santa_Gifts__c'));
        result.put('showSanta', isSantaApplicable(caseRecord, accountRecord));
        result.put('items', items);
        result.put('sectionNotes', loadSectionNotes(caseId, scheduleId));
        result.put('serviceOptions', loadServiceOptions());
        result.put('categoryOptions', activePicklistOptions(SERVICE_OBJECT, 'Category__c'));
        result.put('genderOptions', activePicklistOptions(SERVICE_OBJECT, 'Gender__c'));
        result.put('isChristmasCase', isChristmasCase(caseRecord));
        result.put('readOnly', readOnly);
        result.put('interviewReady', (Id)schedule.get('Assigned_Volunteer__c') != null);
        result.put('isSystemAdministrator', systemAdministrator);
        result.put('notReadyMessage', buildReadOnlyMessage(schedule, systemAdministrator, readOnly));
        result.put('otherBedNeeds', loadOtherBedNeeds(caseId, scheduleId));
        result.put('householdRecommendation', loadHouseholdRecommendation(caseRecord, items));
        result.put('persistedHouseholdRecommendation', stringValue(fieldValue(caseRecord, CASE_RECOMMENDATION_FIELD)));
        result.put('persistenceVersion', PERSISTENCE_VERSION);
        result.put('applicantEmployment', buildApplicantEmployment(caseRecord, accountRecord));
        result.put('caseNotes', buildCaseNotes(caseRecord, caseId));
        result.put('form2026FieldsAvailable', fieldExists(DELIVERY_OBJECT, OTHER_BED_NEEDS_FIELD));
        result.put('formRevision', 0);
        result.put('referenceSelections', new Map<String, Object>());
        result.put('configWarnings', buildConfigWarnings());
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> saveInterview(
        Id recordId,
        String itemsJson,
        String sectionNotesJson,
        String whyHelp,
        String whyNotHelp,
        Boolean santaInterest,
        Boolean completeInterview
    ) {
        if(recordId == null) {
            throw new AuraHandledException('A Case or Interview Day Schedule record is required.');
        }

        Boolean systemAdministrator = isSystemAdministrator();
        Id caseId;
        Id scheduleId;

        if(recordId.getSObjectType() == Case.SObjectType) {
            caseId = recordId;
            scheduleId = findScheduleForCase(caseId);
        } else if(recordId.getSObjectType() == Interview_Day_Schedule__c.SObjectType) {
            scheduleId = recordId;
            SObject scheduleLink = Database.query(
                'SELECT Id, Case__c FROM Interview_Day_Schedule__c WHERE Id = :scheduleId LIMIT 1'
            );
            caseId = (Id)scheduleLink.get('Case__c');
        } else {
            throw new AuraHandledException('Open this component from a Case or Interview Day Schedule record.');
        }

        if(scheduleId == null || caseId == null) {
            throw new AuraHandledException('The interview context could not be resolved.');
        }

        SObject schedule = loadSchedule(scheduleId);
        if((Boolean)schedule.get('Booked__c') != true) {
            throw new AuraHandledException('The Home Interview cannot be edited until the interview is scheduled.');
        }

        enforceVolunteerAccess(schedule, systemAdministrator);
        if(!canEditInterview(schedule, systemAdministrator) || isLifecycleReadOnly(schedule)) {
            throw new AuraHandledException('This Home Interview is read only.');
        }

        Map<String, Object> form = formEnvelope(sectionNotesJson);
        if(form != null && form.containsKey('householdRecommendation')) {
            form.put('householdRecommendation', stringValue(form.get('householdRecommendation')).trim());
        }
        Savepoint savepoint = Database.setSavepoint();
        try {
            // V3 clients submit a baseline so an older draft cannot overwrite a
            // newer Case-level answer. Older clients keep their existing contract.
            validateRecommendationBaseline(caseId, form);
            saveCaseResponses(caseId, whyHelp, whyNotHelp, santaInterest, form);

            Map<String, Id> savedItemIds = new Map<String, Id>();
            if(form == null) {
                saveItems(caseId, scheduleId, itemsJson, sectionNotesJson);
            } else {
                if(completeInterview == true && String.isBlank(stringValue(form.get('householdRecommendation')))) {
                    throw new AuraHandledException('Select an interviewer recommendation before completing the interview.');
                }
                savedItemIds = saveItems2026(caseId, scheduleId, itemsJson, sectionNotesJson, form);
            }

            if(completeInterview == true) {
                completeSchedule(scheduleId);
                completeChristmasCase(caseId);
            } else {
                markScheduleInProgress(scheduleId, stringValue(schedule.get('Assignment_Status__c')));
            }

            // Return a fresh snapshot from the same transaction. The client no
            // longer clears its draft and performs a second, competing reload.
            Map<String, Object> persistedInterview = loadInterview(scheduleId);
            String persistedAnswer = stringValue(persistedInterview.get('persistedHouseholdRecommendation'));
            if(form != null && form.containsKey('householdRecommendation')) {
                String requestedAnswer = stringValue(form.get('householdRecommendation')).trim();
                if(!requestedAnswer.equals(persistedAnswer)) {
                    throw new AuraHandledException(
                        'The recommendation was not retained on the Case. No interview changes were saved. ' +
                        'Check automation that updates Home_Interview_Recommendation__c.'
                    );
                }
            }

            return new Map<String, Object>{
                'success' => true,
                'caseId' => caseId,
                'scheduleId' => scheduleId,
                'completed' => completeInterview == true,
                'assignmentStatus' => completeInterview == true ? 'Completed' : 'In Progress',
                'formRevision' => 0,
                'savedItemIds' => savedItemIds,
                'persistenceVersion' => PERSISTENCE_VERSION,
                'persistedHouseholdRecommendation' => persistedAnswer,
                'interview' => persistedInterview
            };
        } catch(Exception ex) {
            Database.rollback(savepoint);
            throw new AuraHandledException(ex.getMessage());
        }
    }

    private static Id findScheduleForCase(Id caseId) {
        List<SObject> rows = Database.query(
            'SELECT Id FROM Interview_Day_Schedule__c' +
            ' WHERE Case__c = :caseId AND Booked__c = true' +
            ' ORDER BY Interview_Date__c DESC, Start_Time__c DESC LIMIT 1'
        );
        return rows.isEmpty() ? null : (Id)rows[0].get('Id');
    }

    private static SObject loadSchedule(Id scheduleId) {
        List<String> fields = new List<String>{
            'Id',
            'Name',
            'Case__c',
            'Booked__c',
            'Interview_Date__c',
            'Schedule_Mode__c',
            'Start_Time__c',
            'End_Time__c',
            'Assignment_Status__c',
            'Assigned_Volunteer__c'
        };

        if(fieldExists(SCHEDULE_OBJECT, 'Assigned_Volunteer__c')) {
            fields.add('Assigned_Volunteer__r.Name');
        }
        if(fieldExists(SCHEDULE_OBJECT, 'Zone__c')) {
            fields.add('Zone__c');
            fields.add('Zone__r.Name');
        }
        if(fieldExists(SCHEDULE_OBJECT, 'Interview_Day__c')) {
            fields.add('Interview_Day__c');
            fields.add('Interview_Day__r.Zone__c');
            fields.add('Interview_Day__r.Zone__r.Name');
        }

        return Database.query(
            'SELECT ' + String.join(fields, ',') +
            ' FROM Interview_Day_Schedule__c WHERE Id = :scheduleId LIMIT 1'
        );
    }

    private static Map<String, Object> buildNotReadyResponse(Id caseId, String message) {
        SObject caseRecord = loadCase(caseId);
        SObject accountRecord = loadAccount((Id)caseRecord.get('AccountId'));

        return new Map<String, Object>{
            'caseId' => caseId,
            'scheduleId' => null,
            'caseNumber' => stringValue(caseRecord.get('CaseNumber')),
            'householdName' => accountRecord == null ? '' : stringValue(accountRecord.get('Name')),
            'address' => buildAddress(accountRecord),
            'interviewDate' => null,
            'scheduleMode' => '',
            'startTime' => null,
            'endTime' => null,
            'zoneName' => '',
            'interviewerName' => '',
            'intervieweeName' => relationshipName(caseRecord, 'Contact'),
            'intervieweePhone' => relationshipField(caseRecord, 'Contact', 'Phone'),
            'contactPhone' => stringValue(caseRecord.get('ContactPhone')),
            'contactEmail' => stringValue(caseRecord.get('ContactEmail')),
            'assignmentStatus' => 'Unassigned',
            'whyHelp' => fieldValue(caseRecord, 'Why_Help__c'),
            'whyNotHelp' => fieldValue(caseRecord, 'Why_Not_Help__c'),
            'whyHelpFieldAvailable' => fieldExists('Case', 'Why_Help__c'),
            'whyNotHelpFieldAvailable' => fieldExists('Case', 'Why_Not_Help__c'),
            'santaInterest' => booleanValue(fieldValue(caseRecord, 'Interested_in_Santa_Gifts__c')),
            'santaFieldAvailable' => fieldExists('Case', 'Interested_in_Santa_Gifts__c'),
            'showSanta' => isSantaApplicable(caseRecord, accountRecord),
            'items' => new List<Map<String, Object>>(),
            'sectionNotes' => blankSectionNotes(),
            'serviceOptions' => loadServiceOptions(),
            'categoryOptions' => activePicklistOptions(SERVICE_OBJECT, 'Category__c'),
            'genderOptions' => activePicklistOptions(SERVICE_OBJECT, 'Gender__c'),
            'isChristmasCase' => isChristmasCase(caseRecord),
            'readOnly' => true,
            'interviewReady' => false,
            'isSystemAdministrator' => isSystemAdministrator(),
            'notReadyMessage' => message,
            'otherBedNeeds' => '',
            'householdRecommendation' => loadHouseholdRecommendation(caseRecord, null),
            'persistedHouseholdRecommendation' => stringValue(fieldValue(caseRecord, CASE_RECOMMENDATION_FIELD)),
            'persistenceVersion' => PERSISTENCE_VERSION,
            'applicantEmployment' => buildApplicantEmployment(caseRecord, accountRecord),
            'caseNotes' => buildCaseNotes(caseRecord, caseId),
            'form2026FieldsAvailable' => fieldExists(DELIVERY_OBJECT, OTHER_BED_NEEDS_FIELD),
            'formRevision' => 0,
            'referenceSelections' => new Map<String, Object>(),
            'configWarnings' => buildConfigWarnings()
        };
    }

    private static void enforceVolunteerAccess(SObject schedule, Boolean systemAdministrator) {
        Id assignedVolunteerId = (Id)schedule.get('Assigned_Volunteer__c');
        String assignmentStatus = stringValue(schedule.get('Assignment_Status__c'));

        if(assignedVolunteerId == null) {
            throw new AuraHandledException('The Home Interview cannot be edited until a volunteer is assigned.');
        }
        if(!systemAdministrator && assignedVolunteerId != currentUserId()) {
            throw new AuraHandledException('This Home Interview is assigned to another volunteer.');
        }
        if(assignmentStatus == 'Canceled') {
            throw new AuraHandledException('This Home Interview has been canceled.');
        }
    }

    private static Boolean canEditInterview(SObject schedule, Boolean systemAdministrator) {
        if((Boolean)schedule.get('Booked__c') != true) return false;

        Id assignedVolunteerId = (Id)schedule.get('Assigned_Volunteer__c');
        if(assignedVolunteerId == null) return false;

        String assignmentStatus = stringValue(schedule.get('Assignment_Status__c'));
        if(
            assignmentStatus == 'Canceled' ||
            assignmentStatus == 'Reviewed' ||
            assignmentStatus == 'Completed'
        ) return false;

        return systemAdministrator || assignedVolunteerId == currentUserId();
    }

    private static Boolean isLifecycleReadOnly(SObject schedule) {
        String assignmentStatus = stringValue(schedule.get('Assignment_Status__c'));
        return assignmentStatus == 'Completed' ||
            assignmentStatus == 'Reviewed' ||
            assignmentStatus == 'Canceled';
    }

    private static String buildReadOnlyMessage(
        SObject schedule,
        Boolean systemAdministrator,
        Boolean readOnly
    ) {
        if(!readOnly) return '';

        String assignmentStatus = stringValue(schedule.get('Assignment_Status__c'));
        if(assignmentStatus == 'Canceled') return 'This Home Interview has been canceled and is read only.';
        if(assignmentStatus == 'Reviewed') return 'This Home Interview has been reviewed and is read only.';
        if(assignmentStatus == 'Completed') return 'This Home Interview has been completed and is read only.';

        Id assignedVolunteerId = (Id)schedule.get('Assigned_Volunteer__c');
        if(assignedVolunteerId == null) {
            return 'This Home Interview is read only until a volunteer is assigned.';
        }
        if(!systemAdministrator && assignedVolunteerId != currentUserId()) {
            return 'This Home Interview is read only because it is assigned to another volunteer.';
        }
        return 'This Home Interview is read only.';
    }

    private static List<String> buildConfigWarnings() {
        List<String> warnings = new List<String>();

        if(!fieldExists('Case', CASE_RECOMMENDATION_FIELD)) {
            warnings.add('Case.Home_Interview_Recommendation__c is required for the overall interview answer.');
        } else {
            Schema.DescribeFieldResult recommendationAccess =
                Case.SObjectType.getDescribe().fields.getMap().get(CASE_RECOMMENDATION_FIELD).getDescribe();
            if(!recommendationAccess.isAccessible() || !recommendationAccess.isUpdateable()) {
                warnings.add('Your existing profile or permission set needs Read/Edit access to Home Interview Recommendation.');
            }
        }


        if(!fieldExists('Case', 'Why_Help__c')) {
            warnings.add('Case.Why_Help__c is not available.');
        }

        if(!fieldExists('Case', 'Why_Not_Help__c')) {
            warnings.add('Case.Why_Not_Help__c is not available.');
        }

        if(!fieldExists('Case', 'Interested_in_Santa_Gifts__c')) {
            warnings.add('Case.Interested_in_Santa_Gifts__c is not available.');
        }

        if(!fieldExists(DELIVERY_OBJECT, 'Volunteer_Recommendation__c')) {
            warnings.add('Service Delivery volunteer recommendation field is not available.');
        }

        if(!fieldExists(DELIVERY_OBJECT, DELIVERY_NOTES_FIELD)) {
            warnings.add('Service Delivery Notes__c field is not available.');
        }

        if(!fieldExists(DELIVERY_OBJECT, OTHER_BED_NEEDS_FIELD)) {
            warnings.add('Service Delivery Other_Bed_Needs__c field is not available.');
        }

        return warnings;
    }

    private static Boolean isSystemAdministrator() {
        if(systemAdministratorOverride != null) return systemAdministratorOverride;

        Profile currentProfile = [
            SELECT Name
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ];
        return currentProfile.Name == SYSTEM_ADMINISTRATOR_PROFILE;
    }

    private static Id currentUserId() {
        return currentUserIdOverride == null ? UserInfo.getUserId() : currentUserIdOverride;
    }

    private static SObject loadCase(Id caseId) {
        List<String> fields = new List<String>{
            'Id',
            'CaseNumber',
            'Status',
            'AccountId',
            'ContactId',
            'Contact.Name',
            'Contact.Phone',
            'ContactPhone',
            'ContactEmail',
            'RecordType.Name'
        };

        for(String fieldApi : new List<String>{
            CASE_RECOMMENDATION_FIELD,
            'Why_Help__c',
            'Why_Not_Help__c',
            'Interested_in_Santa_Gifts__c',
            'Applicant_Employment_Status__c',
            'Employment_Length_Months__c',
            'Total_Time_Employed_Months__c',
            'Jobs_In_Past_36_Months__c',
            'Applicant_Employer_Name__c',
            'Applicant_Previous_Employer__c',
            'Applicant_Employment_Duration__c',
            'How_long_have_you_lived_at_this_address__c',
            'How_long_did_you_live_there__c'
        }) {
            if(fieldExists('Case', fieldApi)) fields.add(fieldApi);
        }

        String homeVisitNotesField = resolveFieldApi(
            'Case',
            new List<String>{'Home_Visit_Notes__c', 'home_visit_notes__c'}
        );
        if(String.isNotBlank(homeVisitNotesField) && !fields.contains(homeVisitNotesField)) {
            fields.add(homeVisitNotesField);
        }

        return Database.query(
            'SELECT ' + String.join(fields, ',') +
            ' FROM Case WHERE Id = :caseId LIMIT 1'
        );
    }

    private static SObject loadAccount(Id accountId) {
        if(accountId == null) return null;

        List<String> fields = new List<String>{
            'Id',
            'Name',
            'BillingStreet',
            'BillingCity',
            'BillingState',
            'BillingPostalCode',
            'ShippingStreet',
            'ShippingCity',
            'ShippingState',
            'ShippingPostalCode'
        };

        for(String apiName : santaAccountFields()) {
            if(fieldExists('Account', apiName)) fields.add(apiName);
        }

        return Database.query(
            'SELECT ' + String.join(fields, ',') +
            ' FROM Account WHERE Id = :accountId LIMIT 1'
        );
    }

    private static List<Map<String, Object>> loadServiceOptions() {
        List<String> serviceFields = new List<String>{'Id', 'Name'};
        for(String fieldApi : new List<String>{
            'Category__c',
            'Subcategory__c',
            'Gender__c',
            'Furniture_User_Entry__c',
            'Appliances_User_Entry__c'
        }) {
            if(fieldExists(SERVICE_OBJECT, fieldApi)) serviceFields.add(fieldApi);
        }

        List<Map<String, Object>> options = new List<Map<String, Object>>();
        for(SObject service : Database.query(
            'SELECT ' + String.join(serviceFields, ',') +
            ' FROM pmdm__Service__c ORDER BY Name ASC LIMIT 2000'
        )) {
            options.add(new Map<String, Object>{
                'label' => buildServiceDisplayLabel(service),
                'name' => stringValue(service.get('Name')),
                'value' => stringValue(service.get('Id')),
                'category' => stringValue(fieldValue(service, 'Category__c')),
                'subcategory' => stringValue(fieldValue(service, 'Subcategory__c')),
                'gender' => stringValue(fieldValue(service, 'Gender__c')),
                'sectionKey' => classifyServiceSection(service)
            });
        }
        return options;
    }

    private static List<Map<String, Object>> loadServiceDeliveries(Id caseId, Id scheduleId) {
        List<String> fields = new List<String>{
            'Id',
            'Case__c',
            'pmdm__Service__c',
            'pmdm__Service__r.Name',
            'Quantity__c',
            'Status__c',
            'Interview_Day_Schedule__c',
            'Volunteer_Recommendation__c',
            'HGH_Approval__c',
            'HGH_Approval_Overridden__c',
            'HGH_Approval_Reviewed_On__c',
            'LastModifiedDate'
        };

        if(fieldExists(DELIVERY_OBJECT, DELIVERY_NOTES_FIELD)) {
            fields.add(DELIVERY_NOTES_FIELD);
        }

        for(String fieldApi : serviceClassificationFields()) {
            if(fieldExists(SERVICE_OBJECT, fieldApi)) {
                fields.add('pmdm__Service__r.' + fieldApi);
            }
        }

        Set<String> reusableStatuses = new Set<String>{'Requested', 'Scheduled'};

        String queryText =
            'SELECT ' + String.join(fields, ',') +
            ' FROM pmdm__ServiceDelivery__c' +
            ' WHERE Case__c = :caseId' +
            ' AND (Interview_Day_Schedule__c = :scheduleId' +
            ' OR (Interview_Day_Schedule__c = null AND Status__c IN :reusableStatuses))' +
            ' ORDER BY CreatedDate ASC';

        List<Map<String, Object>> items = new List<Map<String, Object>>();

        for(SObject row : Database.query(queryText)) {
            SObject service = row.getSObject('pmdm__Service__r');

            String recommendation = stringValue(row.get('Volunteer_Recommendation__c'));

            if(String.isBlank(recommendation)) {
                recommendation = 'Neutral';
            }

            items.add(new Map<String, Object>{
                'id' => row.get('Id'),
                'serviceId' => row.get('pmdm__Service__c'),
                'serviceName' => buildServiceDisplayLabel(service),
                'sectionKey' => classifyServiceSection(service),
                'category' => stringValue(fieldValue(service, 'Category__c')),
                'subcategory' => stringValue(fieldValue(service, 'Subcategory__c')),
                'gender' => stringValue(fieldValue(service, 'Gender__c')),
                'customEntry' => service == null ? '' : firstNonBlank(
                    stringValue(fieldValue(service, 'Furniture_User_Entry__c')),
                    stringValue(fieldValue(service, 'Appliances_User_Entry__c'))
                ),
                'quantity' => row.get('Quantity__c'),
                'status' => row.get('Status__c'),
                'recommendation' => recommendation,
                'notes' => fieldExists(DELIVERY_OBJECT, DELIVERY_NOTES_FIELD)
                    ? row.get(DELIVERY_NOTES_FIELD)
                    : null,
                'preliminaryApproval' => recommendationApproves(recommendation) ? 'Yes' : 'No',
                'approval' => row.get('HGH_Approval__c'),
                'overridden' => row.get('HGH_Approval_Overridden__c'),
                'reviewedOn' => row.get('HGH_Approval_Reviewed_On__c'),
                'lastModifiedDate' => row.get('LastModifiedDate'),
                'locked' => deliveryLocked(row),
                'managedByForm' => true,
                'clientKey' => stringValue(row.get('Id'))
            });
        }

        return items;
    }

    private static String buildServiceDisplayLabel(SObject service) {
        if(service == null) return 'Requested Item';

        String category = cleanServiceText(stringValue(fieldValue(service, 'Category__c')));
        String subcategory = cleanServiceText(stringValue(fieldValue(service, 'Subcategory__c')));
        String gender = cleanServiceText(stringValue(fieldValue(service, 'Gender__c')));
        String furnitureEntry = cleanServiceText(stringValue(fieldValue(service, 'Furniture_User_Entry__c')));
        String applianceEntry = cleanServiceText(stringValue(fieldValue(service, 'Appliances_User_Entry__c')));
        String customEntry = String.isNotBlank(furnitureEntry) ? furnitureEntry : applianceEntry;

        String detail = subcategory;
        if(String.isNotBlank(customEntry) && subcategory.toLowerCase().contains('other')) detail = customEntry;

        List<String> parts = new List<String>();
        if(String.isNotBlank(category)) parts.add(category);
        if(String.isNotBlank(detail) && detail.toLowerCase() != category.toLowerCase()) parts.add(detail);
        if(String.isNotBlank(gender) && !String.join(parts, ' ').toLowerCase().contains(gender.toLowerCase())) parts.add(gender);
        if(!parts.isEmpty()) return String.join(parts, ' - ');

        String name = stringValue(service.get('Name')).trim();
        if(String.isNotBlank(name) && !looksLikeSalesforceId(name)) return name;
        return 'Requested Item';
    }

    private static String classifyServiceSection(SObject service) {
        if(service == null) return 'otherItems';

        String category = stringValue(fieldValue(service, 'Category__c')).toLowerCase();
        String subcategory = stringValue(fieldValue(service, 'Subcategory__c')).toLowerCase();
        String label = buildServiceDisplayLabel(service).toLowerCase();
        String text = category + ' ' + subcategory + ' ' + label;

        if(text.contains('pillow') || text.contains('towel') || text.contains('washcloth') || text.contains('linen')) return 'linens';
        if(category.contains('bedding') || text.contains('sheet') || text.contains('blanket') || text.contains('bed-n-bag') || text.contains('comforter')) return 'existingBedding';
        if(
            category.contains('furniture') || category.contains('large appliance') ||
            text.contains('couch') || text.contains('sofa') || text.contains('dresser') ||
            text.contains('refrigerator') || text.contains('washer') || text.contains('dryer') ||
            text.contains('kitchen table') || text.contains('kitchen chair') ||
            text.contains('recliner') || text.contains('stove')
        ) return 'furniture';
        if(
            category.contains('small appliance') || category.contains('household') ||
            text.contains('microwave') || text.contains('toaster') || text.contains('vacuum') ||
            text.contains('flatware') || text.contains('crockpot') || text.contains('air fryer') ||
            text.contains('cooking utensil') || text.contains('can opener') || text.contains('dishes') ||
            text.contains('glassware') || text.contains('pots/pans') ||
            text.contains('silverware') || text.contains('sippy')
        ) return 'smallAppliances';
        if(
            category.contains('bed') || text.contains('mattress') || text.contains('bed frame') || text.contains('box spring') ||
            text.contains('bunkbed') || text.contains('crib') || text.contains('twin') ||
            text.contains('full') || text.contains('queen') || text.contains('king')
        ) return 'newBeds';

        return 'otherItems';
    }

    private static void validateRecommendationBaseline(Id caseId, Map<String, Object> form) {
        if(form == null || !form.containsKey('expectedRecommendation') ||
            !form.containsKey('householdRecommendation') ||
            !fieldExists('Case', CASE_RECOMMENDATION_FIELD)) return;

        List<SObject> rows = Database.query(
            'SELECT Id, ' + CASE_RECOMMENDATION_FIELD +
            ' FROM Case WHERE Id = :caseId FOR UPDATE'
        );
        if(rows.isEmpty()) throw new AuraHandledException('The application Case is no longer available.');
        String current = stringValue(rows[0].get(CASE_RECOMMENDATION_FIELD));
        String expected = stringValue(form.get('expectedRecommendation'));
        String requested = stringValue(form.get('householdRecommendation')).trim();
        if(!current.equals(expected) && !current.equals(requested)) {
            throw new AuraHandledException(
                'The recommendation was changed by another session. Your draft has been retained. ' +
                'Refresh and review the latest Case before saving again.'
            );
        }
    }

    private static void saveCaseResponses(
        Id caseId,
        String whyHelp,
        String whyNotHelp,
        Boolean santaInterest,
        Map<String, Object> form
    ) {
        SObject caseUpdate = Case.SObjectType.newSObject(caseId);
        Boolean hasChanges = false;

        if(fieldExists('Case', 'Why_Help__c')) {
            caseUpdate.put('Why_Help__c', whyHelp);
            hasChanges = true;
        }
        if(fieldExists('Case', 'Why_Not_Help__c')) {
            caseUpdate.put('Why_Not_Help__c', whyNotHelp);
            hasChanges = true;
        }
        if(fieldExists('Case', 'Interested_in_Santa_Gifts__c') && santaInterest != null) {
            caseUpdate.put('Interested_in_Santa_Gifts__c', santaInterest);
            hasChanges = true;
        }

        // The overall answer belongs to the application Case, not to an item.
        // A zero-item draft must round-trip without creating a fake Service Delivery.
        // Older clients without this envelope/key must not clear a saved answer.
        if(form != null && form.containsKey('householdRecommendation')) {
            String recommendation = stringValue(form.get('householdRecommendation')).trim();
            if(String.isNotBlank(recommendation) && !validRecommendation(recommendation)) {
                throw new AuraHandledException('The interviewer recommendation is invalid.');
            }
            if(!fieldExists('Case', CASE_RECOMMENDATION_FIELD)) {
                if(String.isNotBlank(recommendation)) {
                    throw new AuraHandledException(
                        'Case.Home_Interview_Recommendation__c is required to save the overall recommendation.'
                    );
                }
            } else {
                caseUpdate.put(
                    CASE_RECOMMENDATION_FIELD,
                    String.isBlank(recommendation) ? null : recommendation
                );
                hasChanges = true;
            }
        }

        if(hasChanges) Database.update(caseUpdate, AccessLevel.USER_MODE);
    }

    private static Map<String, Object> loadSectionNotes(Id caseId, Id scheduleId) {
    Map<String, Object> notes = blankSectionNotes();

    if(caseId == null || scheduleId == null) {
        return notes;
    }

    if(!fieldExists(DELIVERY_OBJECT, DELIVERY_NOTES_FIELD)) {
        return notes;
    }

    List<String> fields = new List<String>{
        'Id',
        'pmdm__Service__c',
        'pmdm__Service__r.Name',
        'Status__c',
        'Interview_Day_Schedule__c',
        DELIVERY_NOTES_FIELD
    };

    for(String fieldApi : serviceClassificationFields()) {
        if(fieldExists(SERVICE_OBJECT, fieldApi)) {
            fields.add('pmdm__Service__r.' + fieldApi);
        }
    }

    Set<String> reusableStatuses = new Set<String>{'Requested', 'Scheduled'};

    String queryText =
        'SELECT ' + String.join(fields, ',') +
        ' FROM pmdm__ServiceDelivery__c' +
        ' WHERE Case__c = :caseId' +
        ' AND (Interview_Day_Schedule__c = :scheduleId' +
        ' OR (Interview_Day_Schedule__c = null AND Status__c IN :reusableStatuses))' +
        ' ORDER BY CreatedDate ASC';

    for(SObject row : Database.query(queryText)) {
        SObject service = row.getSObject('pmdm__Service__r');

        String sectionKey = classifyServiceSection(service);
        String existingNote = stringValue(notes.get(sectionKey));
        String noteValue = stringValue(row.get(DELIVERY_NOTES_FIELD));

        if(String.isBlank(existingNote) && String.isNotBlank(noteValue)) {
            notes.put(sectionKey, noteValue);
        }
    }

    return notes;
}

    private static Map<String, Object> blankSectionNotes() {
    Map<String, Object> notes = new Map<String, Object>();

    for(String sectionKey : SECTION_KEYS) {
        notes.put(sectionKey, '');
    }

    return notes;
}

    private static Map<String, Object> parseSectionNotes(String sectionNotesJson) {
    Map<String, Object> notes = blankSectionNotes();

    if(String.isBlank(sectionNotesJson)) {
        return notes;
    }

    Map<String, Object> rawNotes =
        (Map<String, Object>) JSON.deserializeUntyped(sectionNotesJson);

    if(rawNotes == null) {
        return notes;
    }

    for(String sectionKey : SECTION_KEYS) {
        if(rawNotes.containsKey(sectionKey)) {
            notes.put(sectionKey, stringValue(rawNotes.get(sectionKey)));
        }
    }

    return notes;
}

    private static List<String> serviceClassificationFields() {
        return new List<String>{
            'Category__c',
            'Subcategory__c',
            'Gender__c',
            'Furniture_User_Entry__c',
            'Appliances_User_Entry__c'
        };
    }

    private static Map<Id, SObject> loadServicesById(Set<Id> serviceIds) {
        Map<Id, SObject> services = new Map<Id, SObject>();
        if(serviceIds == null || serviceIds.isEmpty()) return services;

        List<String> fields = new List<String>{'Id', 'Name'};
        for(String fieldApi : serviceClassificationFields()) {
            if(fieldExists(SERVICE_OBJECT, fieldApi)) fields.add(fieldApi);
        }

        String queryText =
            'SELECT ' + String.join(fields, ',') +
            ' FROM pmdm__Service__c' +
            ' WHERE Id IN :serviceIds';

        for(SObject service : Database.query(queryText)) {
            services.put((Id)service.get('Id'), service);
        }

        return services;
    }

    private static void saveItems(Id caseId, Id scheduleId, String itemsJson, String sectionNotesJson) {
        if(String.isBlank(itemsJson)) {
            return;
        }

        List<Object> rawItems = (List<Object>) JSON.deserializeUntyped(itemsJson);

        if(rawItems == null || rawItems.isEmpty()) {
            return;
        }

        Map<String, Object> sectionNotes = parseSectionNotes(sectionNotesJson);

        Set<Id> requestedExistingIds = new Set<Id>();
        Set<Id> serviceIds = new Set<Id>();

        for(Object raw : rawItems) {
            Map<String, Object> item = (Map<String, Object>) raw;

            String idText = (String) item.get('id');
            String serviceIdText = (String) item.get('serviceId');

            if(String.isNotBlank(idText)) {
                requestedExistingIds.add((Id) idText);
            }

            if(String.isNotBlank(serviceIdText)) {
                serviceIds.add((Id) serviceIdText);
            }
        }

        Map<Id, SObject> servicesById = loadServicesById(serviceIds);
        Id currentProgramId = findCurrentYearProgramId();
        CaseDetails caseInfo = loadCaseDetails(caseId);
        String householdName = caseInfo.householdName;
        String engagementTitle = String.isNotBlank(caseInfo.contactName) ? caseInfo.contactName : householdName;
        Id programEngagementId = findOrCreateProgramEngagementId(
            currentProgramId,
            caseInfo.accountId,
            caseInfo.contactId,
            engagementTitle
        );
        Map<Id, SObject> allowedExisting = new Map<Id, SObject>();

        if(!requestedExistingIds.isEmpty()) {
            for(SObject row : Database.query(
                'SELECT Id, Case__c, Interview_Day_Schedule__c, Status__c, ' +
                'HGH_Approval_Overridden__c, HGH_Approval_Reviewed_On__c ' +
                'FROM pmdm__ServiceDelivery__c ' +
                'WHERE Id IN :requestedExistingIds ' +
                'AND Case__c = :caseId ' +
                'AND (Interview_Day_Schedule__c = :scheduleId ' +
                'OR (Interview_Day_Schedule__c = null AND Status__c IN (\'Requested\', \'Scheduled\')))'
            )) {
                allowedExisting.put((Id) row.get('Id'), row);
            }
        }

        Schema.SObjectType deliveryType =
            Schema.getGlobalDescribe().get(DELIVERY_OBJECT);

        List<SObject> inserts = new List<SObject>();
        List<SObject> updates = new List<SObject>();

        for(Object raw : rawItems) {
            Map<String, Object> item = (Map<String, Object>) raw;

            String serviceIdText = (String) item.get('serviceId');

            if(String.isBlank(serviceIdText)) {
                continue;
            }

            Decimal quantity = parseDecimal(item.get('quantity'));

            if(quantity == null || quantity <= 0) {
                throw new AuraHandledException(
                    'Every requested item must have a quantity greater than zero.'
                );
            }

            String recommendation = stringValue(item.get('recommendation'));

            if(String.isBlank(recommendation)) {
                recommendation = 'Neutral';
            }

            if(!validRecommendation(recommendation)) {
                throw new AuraHandledException(
                    'One requested item has an invalid volunteer recommendation.'
                );
            }

            String idText = (String) item.get('id');
            SObject delivery;

            if(String.isNotBlank(idText)) {
                Id deliveryId = (Id) idText;

                if(!allowedExisting.containsKey(deliveryId)) {
                    throw new AuraHandledException(
                        'One requested item is not part of this interview.'
                    );
                }

                SObject existing = allowedExisting.get(deliveryId);

                if(
                    (Boolean) existing.get('HGH_Approval_Overridden__c') == true ||
                    existing.get('HGH_Approval_Reviewed_On__c') != null
                ) {
                    throw new AuraHandledException(
                        'A reviewed household item cannot be changed by the volunteer.'
                    );
                }

                delivery = deliveryType.newSObject(deliveryId);
                delivery.put('Interview_Day_Schedule__c', scheduleId);

            } else {
                delivery = deliveryType.newSObject();
                delivery.put('Case__c', caseId);
                delivery.put('Interview_Day_Schedule__c', scheduleId);
                delivery.put('Status__c', 'Requested');
            }

            if(caseInfo.accountId != null && fieldExists(DELIVERY_OBJECT, 'pmdm__Account__c')) {
                delivery.put('pmdm__Account__c', caseInfo.accountId);
            }
            if(caseInfo.contactId != null && fieldExists(DELIVERY_OBJECT, 'pmdm__Contact__c')) {
                delivery.put('pmdm__Contact__c', caseInfo.contactId);
            }
            if(programEngagementId != null && fieldExists(DELIVERY_OBJECT, 'pmdm__ProgramEngagement__c')) {
                delivery.put('pmdm__ProgramEngagement__c', programEngagementId);
            }

            Id serviceId = (Id) serviceIdText;

            delivery.put('pmdm__Service__c', serviceId);
            delivery.put('Quantity__c', quantity);
            delivery.put('Volunteer_Recommendation__c', recommendation);

            SObject service = servicesById.get(serviceId);
            if(String.isBlank(idText)) {
                delivery.put(
                    'Name',
                    buildServiceDeliveryName(
                        householdName,
                        buildServiceDisplayLabel(service)
                    )
                );
                if(fieldExists(DELIVERY_OBJECT, 'pmdm__AutonameOverride__c')) {
                    delivery.put('pmdm__AutonameOverride__c', true);
                }
            }   
            String sectionKey = classifyServiceSection(service);

            if(fieldExists(DELIVERY_OBJECT, DELIVERY_NOTES_FIELD)) {
                String noteValue = stringValue(sectionNotes.get(sectionKey));

                delivery.put(
                    DELIVERY_NOTES_FIELD,
                    String.isBlank(noteValue) ? null : noteValue
                );
            }

            if(String.isBlank(idText)) {
                inserts.add(delivery);
            } else {
                updates.add(delivery);
            }
        }

        if(!inserts.isEmpty()) {
            Database.insert(inserts, AccessLevel.SYSTEM_MODE);
        }

        if(!updates.isEmpty()) {
            Database.update(updates, AccessLevel.SYSTEM_MODE);
        }
    }
    private static Map<String, Object> formEnvelope(String sectionNotesJson) {
        if(String.isBlank(sectionNotesJson)) return null;
        try {
            Map<String, Object> root = (Map<String, Object>)JSON.deserializeUntyped(sectionNotesJson);
            if(root == null || !root.containsKey('__form2026')) return null;
            Map<String, Object> form = (Map<String, Object>)root.get('__form2026');
            if(form == null) return null;
            return form;
        } catch(Exception ex) {
            throw new AuraHandledException('The interview form data is invalid. Reload the interview and try again.');
        }
    }

    private static String loadOtherBedNeeds(Id caseId, Id scheduleId) {
        if(caseId == null || scheduleId == null || !fieldExists(DELIVERY_OBJECT, OTHER_BED_NEEDS_FIELD)) {
            return '';
        }

        String queryText =
            'SELECT ' + OTHER_BED_NEEDS_FIELD +
            ' FROM pmdm__ServiceDelivery__c' +
            ' WHERE Case__c = :caseId' +
            ' AND Interview_Day_Schedule__c = :scheduleId' +
            ' ORDER BY CreatedDate ASC';

        List<SObject> rows = Database.query(queryText);

        for(SObject row : rows) {
            String otherBedNeeds = stringValue(row.get(OTHER_BED_NEEDS_FIELD));
            if(String.isNotBlank(otherBedNeeds)) {
                return otherBedNeeds;
            }
        }

        return '';
    }

    private static String loadHouseholdRecommendation(
        SObject caseRecord,
        List<Map<String, Object>> items
    ) {
        String savedRecommendation = stringValue(fieldValue(caseRecord, CASE_RECOMMENDATION_FIELD));
        if(String.isNotBlank(savedRecommendation)) return savedRecommendation;

        // Backward-compatible display for historical interviews without a Case-level answer.
        // Mixed item recommendations still return blank; no recommendation is invented.
        return deriveHouseholdRecommendation(items);
    }

    private static String deriveHouseholdRecommendation(List<Map<String, Object>> items) {
        if(items == null || items.isEmpty()) return '';
        String commonValue = '';
        for(Map<String, Object> item : items) {
            String value = stringValue(item.get('recommendation'));
            if(String.isBlank(value)) continue;
            if(String.isBlank(commonValue)) commonValue = value;
            else if(commonValue != value) return '';
        }
        return commonValue;
    }

    private static Boolean deliveryLocked(SObject row) {
        String status = stringValue(row.get('Status__c'));
        return (Boolean)row.get('HGH_Approval_Overridden__c') == true ||
            row.get('HGH_Approval_Reviewed_On__c') != null ||
            (status != 'Requested' && status != 'Scheduled');
    }

    private static Map<String, Id> saveItems2026(
        Id caseId,
        Id scheduleId,
        String itemsJson,
        String sectionNotesJson,
        Map<String, Object> form
    ) {
        List<Object> rawItems;
        try {
            rawItems = String.isBlank(itemsJson)
                ? new List<Object>()
                : (List<Object>)JSON.deserializeUntyped(itemsJson);
        } catch(Exception ex) {
            throw new AuraHandledException('The requested-item data is invalid. Reload the interview and try again.');
        }
        if(rawItems == null) rawItems = new List<Object>();
        if(rawItems.size() > 150) {
            throw new AuraHandledException('Save at most 150 requested items per interview.');
        }

        Map<String, Object> sectionNotes = parseSectionNotes(sectionNotesJson);
        String overallRecommendation = stringValue(form.get('householdRecommendation'));
        if(String.isNotBlank(overallRecommendation) && !validRecommendation(overallRecommendation)) {
            throw new AuraHandledException('The interviewer recommendation is invalid.');
        }

        String otherBedNeeds = stringValue(form.get('otherBedNeeds'));
        if(otherBedNeeds.length() > 32768) {
            throw new AuraHandledException('Other Bed Needs must be 32,768 characters or fewer.');
        }

        Set<Id> requestedIds = new Set<Id>();
        Set<Id> suppliedServiceIds = new Set<Id>();
        for(Object raw : rawItems) {
            Map<String, Object> item = (Map<String, Object>)raw;
            String idText = stringValue(item.get('id'));
            String serviceIdText = stringValue(item.get('serviceId'));
            if(String.isNotBlank(idText)) requestedIds.add((Id)idText);
            if(String.isNotBlank(serviceIdText)) suppliedServiceIds.add((Id)serviceIdText);
        }

        Map<Id, SObject> existingById = new Map<Id, SObject>();
        if(!requestedIds.isEmpty()) {
            for(SObject row : Database.query(
                'SELECT Id, Case__c, Interview_Day_Schedule__c, pmdm__Service__c, Quantity__c, Status__c, ' +
                'Volunteer_Recommendation__c, HGH_Approval_Overridden__c, HGH_Approval_Reviewed_On__c ' +
                'FROM pmdm__ServiceDelivery__c WHERE Id IN :requestedIds AND Case__c = :caseId ' +
                'AND (Interview_Day_Schedule__c = :scheduleId OR ' +
                '(Interview_Day_Schedule__c = null AND Status__c IN (\'Requested\', \'Scheduled\')))' 
            )) {
                existingById.put((Id)row.get('Id'), row);
                Id existingServiceId = (Id)row.get('pmdm__Service__c');
                if(existingServiceId != null) suppliedServiceIds.add(existingServiceId);
            }
        }

        List<Object> removedItems = form.get('removedItems') == null
            ? new List<Object>()
            : (List<Object>)form.get('removedItems');
        if(removedItems.size() > 150) {
            throw new AuraHandledException('Too many removed requests in one save.');
        }

        List<SObject> deletes = new List<SObject>();
        Set<Id> deletedIds = new Set<Id>();
        for(Object raw : removedItems) {
            Map<String, Object> removed = (Map<String, Object>)raw;
            String idText = stringValue(removed.get('id'));
            if(String.isBlank(idText)) continue;
            Id rowId = (Id)idText;
            SObject row = existingById.get(rowId);
            if(row == null) {
                List<SObject> found = Database.query(
                    'SELECT Id, Case__c, Interview_Day_Schedule__c, Status__c, HGH_Approval_Overridden__c, HGH_Approval_Reviewed_On__c ' +
                    'FROM pmdm__ServiceDelivery__c WHERE Id = :rowId AND Case__c = :caseId LIMIT 1'
                );
                if(!found.isEmpty()) row = found[0];
            }
            if(row == null || (Id)row.get('Interview_Day_Schedule__c') != scheduleId) {
                throw new AuraHandledException('Only requests from this interview can be removed.');
            }
            if(deliveryLocked(row) || stringValue(row.get('Status__c')) != 'Requested') {
                throw new AuraHandledException('A reviewed or scheduled request cannot be removed.');
            }
            if(deletedIds.add(rowId)) deletes.add(row);
        }

        Map<Id, SObject> servicesById = loadServicesById(suppliedServiceIds);
        Id currentProgramId;
        Boolean requiresNewService = false;

        // Validate Flow-style category/subcategory values before creating records.
        for(Object raw : rawItems) {
            Map<String, Object> item = (Map<String, Object>)raw;
            String category = stringValue(item.get('category')).trim();
            String subcategory = stringValue(item.get('subcategory')).trim();
            String gender = stringValue(item.get('gender')).trim();
            String customEntry = stringValue(item.get('customEntry')).trim();
            Decimal quantity = parseDecimal(item.get('quantity'));

            if(quantity == null || quantity <= 0 || quantity != quantity.setScale(0)) {
                throw new AuraHandledException('Every requested item must have a positive whole-number quantity.');
            }

            String serviceIdText = stringValue(item.get('serviceId'));
            if(String.isBlank(category) && String.isNotBlank(serviceIdText) && servicesById.containsKey((Id)serviceIdText)) {
                SObject service = servicesById.get((Id)serviceIdText);
                category = stringValue(fieldValue(service, 'Category__c')).trim();
                subcategory = stringValue(fieldValue(service, 'Subcategory__c')).trim();
                gender = stringValue(fieldValue(service, 'Gender__c')).trim();
            }

            validateFlowRequest(category, subcategory, gender, customEntry);

            String idText = stringValue(item.get('id'));
            Boolean mustCreateService = String.isBlank(serviceIdText);
            if(!mustCreateService && String.isNotBlank(idText)) {
                SObject existingDelivery = existingById.get((Id)idText);
                Id existingServiceId = existingDelivery == null ? null : (Id)existingDelivery.get('pmdm__Service__c');
                SObject existingService = existingServiceId == null ? null : servicesById.get(existingServiceId);
                if(existingService != null && !sameServiceDefinition(existingService, category, subcategory, gender, customEntry)) {
                    mustCreateService = true;
                }
            }
            if(mustCreateService) requiresNewService = true;
        }

        currentProgramId = findCurrentYearProgramId();
        if(requiresNewService && currentProgramId == null) {
            throw new AuraHandledException('A program for the current year must exist before creating a service.');
        }

        CaseDetails caseInfo = loadCaseDetails(caseId);
        String householdName = caseInfo.householdName;
        String engagementTitle = String.isNotBlank(caseInfo.contactName) ? caseInfo.contactName : householdName;
        Id programEngagementId = findOrCreateProgramEngagementId(
            currentProgramId,
            caseInfo.accountId,
            caseInfo.contactId,
            engagementTitle
        );
        List<SObject> servicesToInsert = new List<SObject>();
        List<Integer> newServiceItemIndexes = new List<Integer>();

        for(Integer index = 0; index < rawItems.size(); index++) {
            Map<String, Object> item = (Map<String, Object>)rawItems[index];
            String serviceIdText = stringValue(item.get('serviceId'));
            String idText = stringValue(item.get('id'));
            String category = stringValue(item.get('category')).trim();
            String subcategory = stringValue(item.get('subcategory')).trim();
            String gender = stringValue(item.get('gender')).trim();
            String customEntry = stringValue(item.get('customEntry')).trim();
            Decimal quantity = parseDecimal(item.get('quantity'));

            if(String.isBlank(category) && String.isNotBlank(serviceIdText) && servicesById.containsKey((Id)serviceIdText)) {
                SObject service = servicesById.get((Id)serviceIdText);
                category = stringValue(fieldValue(service, 'Category__c')).trim();
                subcategory = stringValue(fieldValue(service, 'Subcategory__c')).trim();
                gender = stringValue(fieldValue(service, 'Gender__c')).trim();
            }

            Boolean mustCreateService = String.isBlank(serviceIdText);
            if(!mustCreateService && String.isNotBlank(idText)) {
                SObject existingDelivery = existingById.get((Id)idText);
                Id existingServiceId = existingDelivery == null ? null : (Id)existingDelivery.get('pmdm__Service__c');
                SObject existingService = existingServiceId == null ? null : servicesById.get(existingServiceId);
                if(existingService != null && !sameServiceDefinition(existingService, category, subcategory, gender, customEntry)) {
                    mustCreateService = true;
                }
            }

            if(mustCreateService) {
                SObject newService = buildFlowService(
                    householdName,
                    currentProgramId,
                    category,
                    subcategory,
                    gender,
                    customEntry,
                    quantity
                );
                servicesToInsert.add(newService);
                newServiceItemIndexes.add(index);
            }
        }

        if(!servicesToInsert.isEmpty()) {
            Database.insert(servicesToInsert, AccessLevel.SYSTEM_MODE);
            for(Integer i = 0; i < servicesToInsert.size(); i++) {
                Map<String, Object> item = (Map<String, Object>)rawItems[newServiceItemIndexes[i]];
                Id newServiceId = (Id)servicesToInsert[i].get('Id');
                item.put('serviceId', String.valueOf(newServiceId));
                servicesById.put(newServiceId, servicesToInsert[i]);
            }
        }

        Schema.SObjectType deliveryType = Schema.getGlobalDescribe().get(DELIVERY_OBJECT);
        List<SObject> inserts = new List<SObject>();
        List<String> insertClientKeys = new List<String>();
        List<SObject> updates = new List<SObject>();
        Map<String, Id> savedItemIds = new Map<String, Id>();
        Set<Id> seenExisting = new Set<Id>();

        for(Object raw : rawItems) {
            Map<String, Object> item = (Map<String, Object>)raw;
            String clientKey = stringValue(item.get('clientKey'));
            String serviceIdText = stringValue(item.get('serviceId'));
            if(String.isBlank(serviceIdText)) {
                throw new AuraHandledException('A Service could not be resolved for one requested item.');
            }
            Id serviceId = (Id)serviceIdText;
            SObject service = servicesById.get(serviceId);
            if(service == null) {
                throw new AuraHandledException('A selected Service is unavailable. Reload the interview and try again.');
            }

            Decimal quantity = parseDecimal(item.get('quantity'));
            String recommendation = String.isBlank(overallRecommendation)
                ? stringValue(item.get('recommendation'))
                : overallRecommendation;
            if(String.isBlank(recommendation)) recommendation = 'Neutral';
            if(!validRecommendation(recommendation)) {
                throw new AuraHandledException('The interviewer recommendation is invalid.');
            }

            String idText = stringValue(item.get('id'));
            SObject delivery;
            if(String.isNotBlank(idText)) {
                Id deliveryId = (Id)idText;
                SObject existing = existingById.get(deliveryId);
                if(existing == null || deletedIds.contains(deliveryId) || !seenExisting.add(deliveryId)) {
                    throw new AuraHandledException('One requested item is not part of this interview.');
                }
                if(deliveryLocked(existing)) {
                    if(stringValue(existing.get('pmdm__Service__c')) != serviceIdText ||
                       parseDecimal(existing.get('Quantity__c')) != quantity ||
                       stringValue(existing.get('Volunteer_Recommendation__c')) != recommendation) {
                        throw new AuraHandledException('A reviewed household item cannot be changed by the volunteer.');
                    }
                    if(String.isNotBlank(clientKey)) savedItemIds.put(clientKey, deliveryId);
                    continue;
                }
                delivery = deliveryType.newSObject(deliveryId);
                delivery.put('Interview_Day_Schedule__c', scheduleId);
            } else {
                delivery = deliveryType.newSObject();
                delivery.put('Case__c', caseId);
                delivery.put('Interview_Day_Schedule__c', scheduleId);
                delivery.put('Status__c', 'Requested');
            }

            if(caseInfo.accountId != null && fieldExists(DELIVERY_OBJECT, 'pmdm__Account__c')) {
                delivery.put('pmdm__Account__c', caseInfo.accountId);
            }
            if(caseInfo.contactId != null && fieldExists(DELIVERY_OBJECT, 'pmdm__Contact__c')) {
                delivery.put('pmdm__Contact__c', caseInfo.contactId);
            }
            if(programEngagementId != null && fieldExists(DELIVERY_OBJECT, 'pmdm__ProgramEngagement__c')) {
                delivery.put('pmdm__ProgramEngagement__c', programEngagementId);
            }

            delivery.put('pmdm__Service__c', serviceId);
            delivery.put('Quantity__c', quantity);
            delivery.put('Volunteer_Recommendation__c', recommendation);

            String sectionKey = stringValue(item.get('section'));
            if(!SECTION_KEYS.contains(sectionKey)) sectionKey = sectionForCategory(stringValue(item.get('category')));
            if(!SECTION_KEYS.contains(sectionKey)) sectionKey = classifyServiceSection(service);
            if(fieldExists(DELIVERY_OBJECT, DELIVERY_NOTES_FIELD)) {
                String noteValue = stringValue(sectionNotes.get(sectionKey));
                delivery.put(DELIVERY_NOTES_FIELD, String.isBlank(noteValue) ? null : noteValue);
            }

            if(String.isBlank(idText)) {
                delivery.put('Name', buildServiceDeliveryName(householdName, buildServiceDisplayLabel(service)));
                if(fieldExists(DELIVERY_OBJECT, 'pmdm__AutonameOverride__c')) {
                    delivery.put('pmdm__AutonameOverride__c', true);
                }
                inserts.add(delivery);
                insertClientKeys.add(clientKey);
            } else {
                updates.add(delivery);
                if(String.isNotBlank(clientKey)) savedItemIds.put(clientKey, (Id)delivery.get('Id'));
            }
        }

        if(!deletes.isEmpty()) Database.delete(deletes, true);
        if(!inserts.isEmpty()) {
            Database.insert(inserts, AccessLevel.SYSTEM_MODE);
            for(Integer i = 0; i < inserts.size(); i++) {
                if(String.isNotBlank(insertClientKeys[i])) {
                    savedItemIds.put(insertClientKeys[i], (Id)inserts[i].get('Id'));
                }
            }
        }
        if(!updates.isEmpty()) Database.update(updates, AccessLevel.SYSTEM_MODE);

        saveOtherBedNeeds(caseId, scheduleId, otherBedNeeds);
        return savedItemIds;
    }

    private static void validateFlowRequest(
        String category,
        String subcategory,
        String gender,
        String customEntry
    ) {
        Map<String, Set<String>> allowed = flowSubcategories();
        Set<String> directQuantityCategories = new Set<String>{'Pillows', 'Towels', 'Washcloths'};
        if(!allowed.containsKey(category) && !directQuantityCategories.contains(category)) {
            throw new AuraHandledException('Choose a valid request category.');
        }
        if(allowed.containsKey(category)) {
            if(String.isBlank(subcategory) || !allowed.get(category).contains(subcategory)) {
                throw new AuraHandledException('Choose a valid subcategory for ' + category + '.');
            }
        }
        if((category == 'Beds' || category == 'Bedding') && String.isBlank(gender)) {
            throw new AuraHandledException('Gender is required for Beds and Bedding requests.');
        }
        if(subcategory == 'Other' && String.isBlank(customEntry)) {
            throw new AuraHandledException('Enter the requested item when Other is selected.');
        }
    }

    private static Map<String, Set<String>> flowSubcategories() {
        return new Map<String, Set<String>>{
            'Beds' => new Set<String>{'Twin', 'Full', 'Queen', 'King', 'Bunkbed', 'Crib'},
            'Bedding' => new Set<String>{'Twin', 'Full', 'Queen', 'King', 'Crib'},
            'Mattress Only' => new Set<String>{'Twin', 'Full', 'Queen', 'King'},
            'Bed Frame Only' => new Set<String>{'Twin', 'Full', 'Queen', 'King'},
            'Furniture' => new Set<String>{
                'Kitchen table', 'Kitchen chairs', 'Washer', 'Dryer', 'Refridgerator',
                'Couch', 'Dresser', 'Other'
            },
            'Small Appliance' => new Set<String>{
                'Pots/Pans', 'Dishes', 'Glassware', 'Microwave', 'Toaster', 'Vacuum',
                'Flatware', 'Crockpot', 'Air Fryer', 'Dishes - Melamine',
                'Cooking Utensils', 'Electric Can Opener', 'Other'
            }
        };
    }

    private static String sectionForCategory(String category) {
        if(category == 'Beds' || category == 'Mattress Only' || category == 'Bed Frame Only') return 'newBeds';
        if(category == 'Bedding') return 'existingBedding';
        if(category == 'Pillows' || category == 'Towels' || category == 'Washcloths') return 'linens';
        if(category == 'Small Appliance') return 'smallAppliances';
        if(category == 'Furniture') return 'furniture';
        return 'otherItems';
    }

    private static Boolean sameServiceDefinition(
        SObject service,
        String category,
        String subcategory,
        String gender,
        String customEntry
    ) {
        if(service == null) return false;
        if(stringValue(fieldValue(service, 'Category__c')).trim() != category) return false;
        if(stringValue(fieldValue(service, 'Subcategory__c')).trim() != subcategory) return false;
        if(stringValue(fieldValue(service, 'Gender__c')).trim() != gender) return false;
        String existingCustom = firstNonBlank(
            stringValue(fieldValue(service, 'Furniture_User_Entry__c')),
            stringValue(fieldValue(service, 'Appliances_User_Entry__c'))
        ).trim();
        return existingCustom == customEntry;
    }

    private static SObject buildFlowService(
        String householdName,
        Id programId,
        String category,
        String subcategory,
        String gender,
        String customEntry,
        Decimal quantity
    ) {
        Schema.SObjectType serviceType = Schema.getGlobalDescribe().get(SERVICE_OBJECT);
        SObject service = serviceType.newSObject();
        service.put('Name', truncateForField(SERVICE_OBJECT, 'Name', householdName + ' ' + category));
        if(fieldExists(SERVICE_OBJECT, 'pmdm__Program__c')) service.put('pmdm__Program__c', programId);
        if(fieldExists(SERVICE_OBJECT, 'Category__c')) service.put('Category__c', category);
        if(fieldExists(SERVICE_OBJECT, 'Subcategory__c')) service.put('Subcategory__c', String.isBlank(subcategory) ? null : subcategory);
        if(fieldExists(SERVICE_OBJECT, 'Gender__c')) service.put('Gender__c', String.isBlank(gender) ? null : gender);
        if(fieldExists(SERVICE_OBJECT, 'Quantity__c')) service.put('Quantity__c', quantity);
        if(category == 'Furniture' && subcategory == 'Other' && fieldExists(SERVICE_OBJECT, 'Furniture_User_Entry__c')) {
            service.put('Furniture_User_Entry__c', customEntry);
        }
        if(category == 'Small Appliance' && subcategory == 'Other' && fieldExists(SERVICE_OBJECT, 'Appliances_User_Entry__c')) {
            service.put('Appliances_User_Entry__c', customEntry);
        }
        return service;
    }

    private static Id findCurrentYearProgramId() {
        Schema.SObjectType programType = Schema.getGlobalDescribe().get('pmdm__Program__c');
        if(programType == null) return null;
        Integer currentYear = Date.today().year();
        String yearText = String.valueOf(currentYear);
        String likeYear = '%' + yearText + '%';

        // Search strictly on standard Name containing current year to avoid matching formula fields evaluating dynamically to TODAY
        List<SObject> rows = Database.query(
            'SELECT Id FROM pmdm__Program__c WHERE Name LIKE :likeYear ORDER BY CreatedDate DESC LIMIT 1'
        );
        if(!rows.isEmpty()) {
            return (Id)rows[0].get('Id');
        }

        // If no program exists for the current year, automatically create it
        SObject newProgram = programType.newSObject();
        newProgram.put('Name', 'Christmas Assistance Program ' + yearText);
        if(fieldExists('pmdm__Program__c', 'pmdm__Status__c')) {
            newProgram.put('pmdm__Status__c', 'Active');
        }
        if(fieldExists('pmdm__Program__c', 'pmdm__StartDate__c')) {
            newProgram.put('pmdm__StartDate__c', Date.newInstance(currentYear, 1, 1));
        }
        if(fieldExists('pmdm__Program__c', 'pmdm__EndDate__c')) {
            newProgram.put('pmdm__EndDate__c', Date.newInstance(currentYear, 12, 31));
        }
        Database.insert(newProgram, AccessLevel.SYSTEM_MODE);
        return (Id)newProgram.get('Id');
    }

    private static String truncateForField(String objectApi, String fieldApi, String value) {
        String text = String.isBlank(value) ? '' : value.trim();
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApi);
        if(objectType == null) return text;
        Schema.SObjectField fieldToken = objectType.getDescribe().fields.getMap().get(fieldApi);
        if(fieldToken == null) return text;
        Integer maxLength = fieldToken.getDescribe().getLength();
        return maxLength > 0 && text.length() > maxLength ? text.substring(0, maxLength) : text;
    }

    private static void saveOtherBedNeeds(Id caseId, Id scheduleId, String otherBedNeeds) {
        if(!fieldExists(DELIVERY_OBJECT, OTHER_BED_NEEDS_FIELD)) {
            if(String.isNotBlank(otherBedNeeds)) {
                throw new AuraHandledException('Service Delivery Other Bed Needs field is not available.');
            }
            return;
        }

        String queryText =
            'SELECT Id, Status__c, HGH_Approval_Overridden__c, HGH_Approval_Reviewed_On__c, ' + OTHER_BED_NEEDS_FIELD +
            ' FROM pmdm__ServiceDelivery__c WHERE Case__c = :caseId AND Interview_Day_Schedule__c = :scheduleId' +
            ' ORDER BY CreatedDate ASC';
        List<SObject> rows = Database.query(queryText);
        if(rows.isEmpty()) {
            if(String.isNotBlank(otherBedNeeds)) {
                throw new AuraHandledException('Add at least one requested item before saving Other Bed Needs.');
            }
            return;
        }

        SObject target;
        for(SObject row : rows) {
            if(!deliveryLocked(row)) {
                target = row;
                break;
            }
        }
        if(target == null) {
            String currentValue = '';
            for(SObject row : rows) {
                if(String.isNotBlank(stringValue(row.get(OTHER_BED_NEEDS_FIELD)))) {
                    currentValue = stringValue(row.get(OTHER_BED_NEEDS_FIELD));
                    break;
                }
            }
            if(currentValue != otherBedNeeds) {
                throw new AuraHandledException('Other Bed Needs cannot be changed after all household requests are reviewed.');
            }
            return;
        }

        List<SObject> changes = new List<SObject>();
        for(SObject row : rows) {
            if(deliveryLocked(row)) continue;
            String desired = (Id)row.get('Id') == (Id)target.get('Id') && String.isNotBlank(otherBedNeeds)
                ? otherBedNeeds
                : null;
            if(stringValue(row.get(OTHER_BED_NEEDS_FIELD)) != stringValue(desired)) {
                SObject updateRow = Schema.getGlobalDescribe().get(DELIVERY_OBJECT).newSObject((Id)row.get('Id'));
                updateRow.put(OTHER_BED_NEEDS_FIELD, desired);
                changes.add(updateRow);
            }
        }
        if(!changes.isEmpty()) Database.update(changes, AccessLevel.SYSTEM_MODE);
    }

    private class CaseDetails {
        public Id accountId;
        public Id contactId;
        public String householdName;
        public String contactName;
    }

    private static CaseDetails loadCaseDetails(Id caseId) {
        CaseDetails cd = new CaseDetails();
        cd.householdName = 'Household';
        cd.contactName = '';
        if(caseId == null) return cd;

        List<Case> caseRows = [
            SELECT Id, AccountId, ContactId, Account.Name, Contact.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if(!caseRows.isEmpty()) {
            Case c = caseRows[0];
            cd.accountId = c.AccountId;
            cd.contactId = c.ContactId;
            if(c.Account != null && String.isNotBlank(c.Account.Name)) {
                cd.householdName = c.Account.Name.trim();
            }
            if(c.Contact != null && String.isNotBlank(c.Contact.Name)) {
                cd.contactName = c.Contact.Name.trim();
            }
        }
        return cd;
    }

    private static String loadHouseholdNameForCase(Id caseId) {
        return loadCaseDetails(caseId).householdName;
    }

    private static Id findOrCreateProgramEngagementId(Id programId, Id accountId, Id contactId, String fallbackName) {
        if(programId == null || (accountId == null && contactId == null)) return null;
        Schema.SObjectType engagementType = Schema.getGlobalDescribe().get('pmdm__ProgramEngagement__c');
        if(engagementType == null) return null;

        List<SObject> existing = new List<SObject>();
        if(accountId != null && contactId != null) {
            existing = Database.query(
                'SELECT Id FROM pmdm__ProgramEngagement__c ' +
                'WHERE pmdm__Program__c = :programId AND (pmdm__Account__c = :accountId OR pmdm__Contact__c = :contactId) ' +
                'ORDER BY CreatedDate DESC LIMIT 1'
            );
        } else if(accountId != null) {
            existing = Database.query(
                'SELECT Id FROM pmdm__ProgramEngagement__c ' +
                'WHERE pmdm__Program__c = :programId AND pmdm__Account__c = :accountId ' +
                'ORDER BY CreatedDate DESC LIMIT 1'
            );
        } else if(contactId != null) {
            existing = Database.query(
                'SELECT Id FROM pmdm__ProgramEngagement__c ' +
                'WHERE pmdm__Program__c = :programId AND pmdm__Contact__c = :contactId ' +
                'ORDER BY CreatedDate DESC LIMIT 1'
            );
        }

        if(!existing.isEmpty()) {
            return (Id)existing[0].get('Id');
        }

        SObject newEngagement = engagementType.newSObject();
        String safeName = String.isBlank(fallbackName) ? 'Program Engagement' : fallbackName.trim();
        newEngagement.put('Name', truncateForField('pmdm__ProgramEngagement__c', 'Name', safeName));
        newEngagement.put('pmdm__Program__c', programId);
        if(accountId != null && fieldExists('pmdm__ProgramEngagement__c', 'pmdm__Account__c')) {
            newEngagement.put('pmdm__Account__c', accountId);
        }
        if(contactId != null && fieldExists('pmdm__ProgramEngagement__c', 'pmdm__Contact__c')) {
            newEngagement.put('pmdm__Contact__c', contactId);
        }
        Database.insert(newEngagement, AccessLevel.SYSTEM_MODE);
        return (Id)newEngagement.get('Id');
    }

    private static String buildServiceDeliveryName(
        String householdName,
        String serviceName
    ) {
        String resolvedHouseholdName = String.isBlank(householdName)
            ? 'Household'
            : householdName.trim();

        String resolvedServiceName = String.isBlank(serviceName)
            ? 'Requested Item'
            : serviceName.trim();

        String dateText = String.valueOf(Date.today());

        String nameValue =
            resolvedHouseholdName +
            ' ' +
            dateText +
            ': ' +
            resolvedServiceName;

        Integer maxLength = 80;

        Schema.SObjectType deliveryType =
            Schema.getGlobalDescribe().get(DELIVERY_OBJECT);

        if(deliveryType != null) {
            Schema.SObjectField nameField =
                deliveryType.getDescribe().fields.getMap().get('Name');

            if(nameField != null) {
                maxLength = nameField.getDescribe().getLength();
            }
        }

        if(maxLength > 0 && nameValue.length() > maxLength) {
            return nameValue.substring(0, maxLength);
        }

        return nameValue;
    }

    private static void markScheduleInProgress(Id scheduleId, String currentStatus) {
        if(currentStatus != 'Assigned') return;

        SObject scheduleUpdate = Schema.getGlobalDescribe().get(SCHEDULE_OBJECT).newSObject(scheduleId);
        scheduleUpdate.put('Assignment_Status__c', 'In Progress');
        Database.update(scheduleUpdate, AccessLevel.SYSTEM_MODE);
    }

    private static void completeSchedule(Id scheduleId) {
        SObject scheduleUpdate = Schema.getGlobalDescribe().get(SCHEDULE_OBJECT).newSObject(scheduleId);
        scheduleUpdate.put('Assignment_Status__c', 'Completed');
        scheduleUpdate.put('Completed_On__c', System.now());
        Database.update(scheduleUpdate, AccessLevel.SYSTEM_MODE);
    }

    private static Boolean validRecommendation(String recommendation) {
        return new Set<String>{
            'Strongly Recommend',
            'Recommend',
            'Neutral',
            'Concerns',
            'Do Not Recommend'
        }.contains(recommendation);
    }

    private static Boolean recommendationApproves(String recommendation) {
        return recommendation == 'Strongly Recommend' ||
            recommendation == 'Recommend' ||
            recommendation == 'Neutral';
    }

    private static Boolean isSantaApplicable(SObject caseRecord, SObject accountRecord) {
        if(fieldExists('Case', 'Interested_in_Santa_Gifts__c') && booleanValue(fieldValue(caseRecord, 'Interested_in_Santa_Gifts__c'))) {
            return true;
        }

        SObject recordType = caseRecord.getSObject('RecordType');
        if(recordType != null) {
            String recordTypeName = stringValue(recordType.get('Name')).toLowerCase();
            if(recordTypeName.contains('christmas') || recordTypeName.contains('santa')) return true;
        }

        if(accountRecord != null) {
            for(String apiName : santaAccountFields()) {
                if(!fieldExists('Account', apiName)) continue;
                Object value = accountRecord.get(apiName);
                if(value instanceof Boolean && (Boolean)value) return true;
                String textValue = stringValue(value).toLowerCase();
                if(
                    textValue == 'true' ||
                    textValue == 'yes' ||
                    textValue.contains('christmas') ||
                    textValue.contains('santa')
                ) return true;
            }
        }
        return false;
    }

    private static List<String> santaAccountFields() {
        List<String> matches = new List<String>();
        Map<String, Schema.SObjectField> fields = Account.SObjectType.getDescribe().fields.getMap();
        Set<String> targetLabels = new Set<String>{
            'Interested in Santa Gifts',
            'Christmas Assistance',
            'Christmas Application Status'
        };

        for(String apiName : fields.keySet()) {
            Schema.DescribeFieldResult info = fields.get(apiName).getDescribe();
            if(targetLabels.contains(info.getLabel())) matches.add(apiName);
        }
        return matches;
    }

    private static List<Map<String, Object>> activePicklistOptions(String objectApi, String fieldApi) {
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApi);
        if(objectType == null) return options;
        Schema.SObjectField fieldToken = objectType.getDescribe().fields.getMap().get(fieldApi);
        if(fieldToken == null) return options;
        for(Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if(entry.isActive()) {
                options.add(new Map<String, Object>{'label' => entry.getLabel(), 'value' => entry.getValue()});
            }
        }
        return options;
    }

    private static Boolean isChristmasCase(SObject caseRecord) {
        if(caseRecord == null) return false;
        SObject recordType = caseRecord.getSObject('RecordType');
        if(recordType == null) return false;
        return stringValue(recordType.get('Name')).toLowerCase().contains('christmas');
    }

    private static void completeChristmasCase(Id caseId) {
        if(caseId == null) return;
        SObject caseRecord = loadCase(caseId);
        if(!isChristmasCase(caseRecord)) return;

        String desiredStatus = '';
        for(Schema.PicklistEntry entry : Case.Status.getDescribe().getPicklistValues()) {
            if(!entry.isActive()) continue;
            String normalizedValue = entry.getValue().trim().toLowerCase();
            String normalizedLabel = entry.getLabel().trim().toLowerCase();
            if(normalizedValue == 'home interview complete' || normalizedLabel == 'home interview complete') {
                desiredStatus = entry.getValue();
                break;
            }
            if(String.isBlank(desiredStatus) &&
               (normalizedValue == 'home interview completed' || normalizedLabel == 'home interview completed')) {
                desiredStatus = entry.getValue();
            }
        }
        if(String.isBlank(desiredStatus)) {
            throw new AuraHandledException('Case Status must include an active Home Interview Complete value for Christmas interviews.');
        }
        Case caseUpdate = new Case(Id = caseId, Status = desiredStatus);
        Database.update(caseUpdate, AccessLevel.SYSTEM_MODE);
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isNotBlank(firstValue) ? firstValue : stringValue(secondValue);
    }

    private static String resolveZoneName(SObject schedule) {
        SObject directZone = schedule.getSObject('Zone__r');
        if(directZone != null) return stringValue(directZone.get('Name'));

        SObject interviewDay = schedule.getSObject('Interview_Day__r');
        if(interviewDay != null) {
            SObject zone = interviewDay.getSObject('Zone__r');
            if(zone != null) return stringValue(zone.get('Name'));
        }
        return '';
    }

    private static Map<String, Object> buildApplicantEmployment(SObject caseRecord, SObject accountRecord) {
        return new Map<String, Object>{
            'applicantName' => relationshipName(caseRecord, 'Contact'),
            'employmentStatus' => stringValue(fieldValue(caseRecord, 'Applicant_Employment_Status__c')),
            'currentEmployer' => stringValue(fieldValue(caseRecord, 'Applicant_Employer_Name__c')),
            'employmentLengthMonths' => stringValue(fieldValue(caseRecord, 'Employment_Length_Months__c')),
            'previousEmployer' => stringValue(fieldValue(caseRecord, 'Applicant_Previous_Employer__c')),
            'previousEmploymentMonths' => stringValue(fieldValue(caseRecord, 'Applicant_Employment_Duration__c')),
            'jobsPast36Months' => stringValue(fieldValue(caseRecord, 'Jobs_In_Past_36_Months__c')),
            'totalTimeEmployedMonths' => stringValue(fieldValue(caseRecord, 'Total_Time_Employed_Months__c')),
            'currentAddress' => buildAddress(accountRecord),
            'currentAddressMonths' => stringValue(fieldValue(caseRecord, 'How_long_have_you_lived_at_this_address__c')),
            'previousAddress' => buildPreviousAddress(accountRecord),
            'previousAddressMonths' => stringValue(fieldValue(caseRecord, 'How_long_did_you_live_there__c'))
        };
    }

    private static List<Map<String, Object>> buildCaseNotes(SObject caseRecord, Id caseId) {
        List<Map<String, Object>> notes = new List<Map<String, Object>>();

        // Salesforce Lightning Notes are Enhanced Notes (ContentNote), not Case fields.
        // Load the Notes related-list records linked to this Case first.
        notes.addAll(loadEnhancedCaseNotes(caseId));

        // Keep existing Case-level context fields as additional read-only notes.
        String homeVisitNotesField = resolveFieldApi(
            'Case',
            new List<String>{'Home_Visit_Notes__c', 'home_visit_notes__c'}
        );
        if(String.isNotBlank(homeVisitNotesField)) {
            addCaseNote(notes, 'Home Visit Notes', stringValue(fieldValue(caseRecord, homeVisitNotesField)));
        }

        // Review narratives remain on Case and in the Review tab, not duplicated here.

        return notes;
    }

    private static List<Map<String, Object>> loadEnhancedCaseNotes(Id caseId) {
        List<Map<String, Object>> notes = new List<Map<String, Object>>();
        if(caseId == null) return notes;

        try {
            Set<Id> contentDocumentIds = new Set<Id>();

            for(ContentDocumentLink linkRow : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :caseId
                AND ContentDocument.FileType = 'SNOTE'
            ]) {
                if(linkRow.ContentDocumentId != null) {
                    contentDocumentIds.add(linkRow.ContentDocumentId);
                }
            }

            if(contentDocumentIds.isEmpty()) return notes;

            for(ContentNote noteRow : [
                SELECT Id, Title, Content, TextPreview, CreatedDate, CreatedBy.Name
                FROM ContentNote
                WHERE Id IN :contentDocumentIds
                ORDER BY CreatedDate DESC
            ]) {
                String noteBody = contentNoteText(noteRow);
                if(String.isBlank(noteBody)) continue;

                notes.add(new Map<String, Object>{
                    'key' => 'content-note-' + String.valueOf(noteRow.Id),
                    'label' => String.isBlank(noteRow.Title) ? 'Case Note' : noteRow.Title,
                    'value' => noteBody
                });
            }
        } catch(Exception ex) {
            // Notes are supporting read-only context. A note-access issue must not
            // prevent the Home Interview itself from loading.
        }

        return notes;
    }

    private static String contentNoteText(ContentNote noteRow) {
        if(noteRow == null) return '';

        String noteBody = '';
        if(noteRow.Content != null) {
            noteBody = noteRow.Content.toString();
        }

        if(String.isBlank(noteBody)) {
            return stringValue(noteRow.TextPreview);
        }

        // Enhanced Notes content is stored as HTML. Convert it to readable plain text
        // because the LWC deliberately renders Case Notes as escaped read-only text.
        noteBody = noteBody.replaceAll('(?i)<br\\s*/?>', '\n');
        noteBody = noteBody.replaceAll('(?i)</p\\s*>', '\n');
        noteBody = noteBody.replaceAll('(?i)</div\\s*>', '\n');
        noteBody = noteBody.stripHtmlTags();
        noteBody = noteBody.replace('&nbsp;', ' ');
        noteBody = noteBody.replace('&amp;', '&');
        noteBody = noteBody.replace('&lt;', '<');
        noteBody = noteBody.replace('&gt;', '>');
        noteBody = noteBody.replace('&quot;', '"');
        noteBody = noteBody.replaceAll('\\n[ \t]*\\n[ \t]*\\n+', '\n\n');

        return noteBody.trim();
    }

    private static void addCaseNote(List<Map<String, Object>> notes, String label, String value) {
        if(String.isBlank(value)) return;
        notes.add(new Map<String, Object>{
            'key' => label.replaceAll('[^A-Za-z0-9]+', '_').toLowerCase(),
            'label' => label,
            'value' => value
        });
    }

    private static String buildPreviousAddress(SObject accountRecord) {
        if(accountRecord == null) return '';

        List<String> parts = new List<String>();
        addIfNotBlank(parts, stringValue(accountRecord.get('ShippingStreet')));
        addIfNotBlank(parts, stringValue(accountRecord.get('ShippingCity')));
        addIfNotBlank(parts, stringValue(accountRecord.get('ShippingState')));
        addIfNotBlank(parts, stringValue(accountRecord.get('ShippingPostalCode')));
        return String.join(parts, ', ');
    }

    private static String resolveFieldApi(String objectApi, List<String> candidates) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApi);
        if(objectType == null || candidates == null) return null;

        Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
        for(String candidate : candidates) {
            if(String.isBlank(candidate)) continue;
            if(fields.containsKey(candidate)) return candidate;
            for(String existingApi : fields.keySet()) {
                if(existingApi.equalsIgnoreCase(candidate)) return existingApi;
            }
        }
        return null;
    }

    private static String buildAddress(SObject accountRecord) {
        if(accountRecord == null) return '';

        List<String> parts = new List<String>();
        addIfNotBlank(parts, stringValue(accountRecord.get('BillingStreet')));
        addIfNotBlank(parts, stringValue(accountRecord.get('BillingCity')));
        addIfNotBlank(parts, stringValue(accountRecord.get('BillingState')));
        addIfNotBlank(parts, stringValue(accountRecord.get('BillingPostalCode')));
        return String.join(parts, ', ');
    }

    private static void addIfNotBlank(List<String> parts, String value) {
        if(String.isNotBlank(value)) parts.add(value);
    }

    private static String cleanServiceText(String value) {
        if(String.isBlank(value)) return '';
        return value.replace(';', ', ').replaceAll('\\s+', ' ').trim();
    }

    private static Boolean looksLikeSalesforceId(String value) {
        if(String.isBlank(value)) return false;
        String trimmed = value.trim();
        Pattern idPattern = Pattern.compile('^[a-zA-Z0-9]+$');
        return (trimmed.length() == 15 || trimmed.length() == 18) && idPattern.matcher(trimmed).matches();
    }

    private static Boolean fieldExists(String objectApi, String fieldApi) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApi);
        return objectType != null && objectType.getDescribe().fields.getMap().containsKey(fieldApi);
    }

    private static Object fieldValue(SObject row, String fieldApi) {
        if(row == null || !row.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApi)) return null;
        return row.get(fieldApi);
    }

    private static String relationshipName(SObject row, String relationshipName) {
        if(row == null) return '';
        SObject related = row.getSObject(relationshipName);
        return related == null ? '' : stringValue(related.get('Name'));
    }

    private static String relationshipField(SObject row, String relationshipName, String fieldApi) {
        if(row == null) return '';
        SObject related = row.getSObject(relationshipName);
        return related == null ? '' : stringValue(related.get(fieldApi));
    }

    private static Decimal parseDecimal(Object value) {
        if(value == null) return null;
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch(Exception ex) {
            return null;
        }
    }

    private static Boolean booleanValue(Object value) {
        if(value == null) return false;
        if(value instanceof Boolean) return (Boolean)value;
        String text = String.valueOf(value).trim().toLowerCase();
        return text == 'true' || text == 'yes' || text == '1';
    }

    private static String stringValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

}