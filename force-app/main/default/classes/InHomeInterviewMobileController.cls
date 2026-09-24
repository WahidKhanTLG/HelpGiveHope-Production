public with sharing class InHomeInterviewMobileController {

    private static final String SCHEDULE_OBJECT = 'Interview_Day_Schedule__c';
    private static final String DELIVERY_OBJECT = 'pmdm__ServiceDelivery__c';
    private static final String SERVICE_OBJECT = 'pmdm__Service__c';
    private static final String SYSTEM_ADMINISTRATOR_PROFILE = 'System Administrator';
    private static final String DELIVERY_NOTES_FIELD = 'Notes__c';

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
                'interviewDate' => valueOrNull(schedule.get('Interview_Date__c')),
                'scheduleMode' => stringValue(schedule.get('Schedule_Mode__c')),
                'startTime' => valueOrNull(schedule.get('Start_Time__c')),
                'endTime' => valueOrNull(schedule.get('End_Time__c')),
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
        result.put('interviewDate', valueOrNull(schedule.get('Interview_Date__c')));
        result.put('scheduleMode', stringValue(schedule.get('Schedule_Mode__c')));
        result.put('startTime', valueOrNull(schedule.get('Start_Time__c')));
        result.put('endTime', valueOrNull(schedule.get('End_Time__c')));
        result.put('zoneName', resolveZoneName(schedule));
        result.put('interviewerName', relationshipName(schedule, 'Assigned_Volunteer__r'));
        result.put('intervieweeName', relationshipName(caseRecord, 'Contact'));
        result.put('intervieweePhone', relationshipField(caseRecord, 'Contact', 'Phone'));
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
        result.put('readOnly', readOnly);
        result.put('interviewReady', (Id)schedule.get('Assigned_Volunteer__c') != null);
        result.put('isSystemAdministrator', systemAdministrator);
        result.put('notReadyMessage', buildReadOnlyMessage(schedule, systemAdministrator, readOnly));
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

        saveCaseResponses(caseId, whyHelp, whyNotHelp, santaInterest);
        saveItems(caseId, scheduleId, itemsJson, sectionNotesJson);

        if(completeInterview == true) {
            completeSchedule(scheduleId);
        } else {
            markScheduleInProgress(scheduleId, stringValue(schedule.get('Assignment_Status__c')));
        }

        return new Map<String, Object>{
            'success' => true,
            'caseId' => caseId,
            'scheduleId' => scheduleId,
            'completed' => completeInterview == true,
            'assignmentStatus' => completeInterview == true ? 'Completed' : 'In Progress'
        };
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
            'readOnly' => true,
            'interviewReady' => false,
            'isSystemAdministrator' => isSystemAdministrator(),
            'notReadyMessage' => message,
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
            'AccountId',
            'ContactId',
            'Contact.Name',
            'Contact.Phone',
            'RecordType.Name'
        };

        for(String fieldApi : new List<String>{
            'Why_Help__c',
            'Why_Not_Help__c',
            'Interested_in_Santa_Gifts__c'
        }) {
            if(fieldExists('Case', fieldApi)) fields.add(fieldApi);
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
            'BillingPostalCode'
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
                'lastModifiedDate' => row.get('LastModifiedDate')
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
            text.contains('kitchen table') || text.contains('kitchen chair')
        ) return 'furniture';
        if(
            category.contains('small appliance') || category.contains('household') ||
            text.contains('microwave') || text.contains('toaster') || text.contains('vacuum') ||
            text.contains('flatware') || text.contains('crockpot') || text.contains('air fryer') ||
            text.contains('cooking utensil') || text.contains('can opener') || text.contains('dishes') ||
            text.contains('glassware') || text.contains('pots/pans')
        ) return 'smallAppliances';
        if(
            category.contains('bed') || text.contains('mattress') || text.contains('bed frame') ||
            text.contains('bunkbed') || text.contains('crib') || text.contains('twin') ||
            text.contains('full') || text.contains('queen') || text.contains('king')
        ) return 'newBeds';

        return 'otherItems';
    }

    private static void saveCaseResponses(
        Id caseId,
        String whyHelp,
        String whyNotHelp,
        Boolean santaInterest
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
        String householdName = loadHouseholdNameForCase(caseId);
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
    private static String loadHouseholdNameForCase(Id caseId) {
        if(caseId == null) {
            return 'Household';
        }

        List<Case> caseRows = [
            SELECT Id, Account.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if(
            caseRows.isEmpty() ||
            caseRows[0].Account == null ||
            String.isBlank(caseRows[0].Account.Name)
        ) {
            return 'Household';
        }

        return caseRows[0].Account.Name.trim();
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

    private static Object valueOrNull(Object value) {
        return value;
    }
}