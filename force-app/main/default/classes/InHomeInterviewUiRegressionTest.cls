@IsTest
private class InHomeInterviewUiRegressionTest {
    private static final String SUBJECT = 'HGH UI Persistence R3 Test';
    private static final String ANSWER_FIELD = 'Home_Interview_Recommendation__c';

    @TestSetup
    static void setupData() {
        Test.setMock(HttpCalloutMock.class, new CalendarMock());
        Id caller = UserInfo.getUserId();
        Schema.SObjectField answer = Case.SObjectType.getDescribe().fields.getMap().get(ANSWER_FIELD);
        System.assertNotEquals(null, answer, 'The existing Case recommendation field is required.');
        System.assert(answer.getDescribe().isAccessible() && answer.getDescribe().isUpdateable(),
            'Grant Read/Edit to the existing field through the deployment user profile or existing permission set.');

        System.runAs(new User(Id = caller)) {
            Account household = new Account(Name = 'HGH R3 Test Household', Census_Tract__c = '98.11');
            insert household;
            Contact applicant = new Contact(FirstName = 'Test', LastName = 'Applicant', AccountId = household.Id);
            insert applicant;
            Case application = new Case(Subject = SUBJECT, Status = firstActive(Case.Status),
                Origin = firstActive(Case.Origin), AccountId = household.Id, ContactId = applicant.Id);
            insert application;
            Zone__c zoneRecord = new Zone__c(Name = 'HGH R3 Test Zone');
            insert zoneRecord;
            Interview_Day__c dayRecord = new Interview_Day__c(
                Interview_Date__c = Date.today().addDays(7), Schedule_Mode__c = 'Morning',
                Total_Slots__c = 2, Status__c = 'Published', Zone__c = zoneRecord.Id);
            insert dayRecord;
            List<Interview_Day_Schedule__c> generated = [
                SELECT Id FROM Interview_Day_Schedule__c WHERE Interview_Day__c = :dayRecord.Id
                ORDER BY Start_Time__c LIMIT 1
            ];
            Interview_Day_Schedule__c slot;
            if(generated.isEmpty()) {
                slot = new Interview_Day_Schedule__c(Name = 'HGH R3 Test Slot', Interview_Day__c = dayRecord.Id,
                    Zone__c = zoneRecord.Id, Start_Time__c = Time.newInstance(8, 0, 0, 0),
                    End_Time__c = Time.newInstance(8, 15, 0, 0));
                insert slot;
            } else {
                slot = generated[0];
            }
            slot.Booked__c = true;
            slot.Case__c = application.Id;
            slot.Assigned_Volunteer__c = caller;
            slot.Assignment_Status__c = 'Assigned';
            update slot;
            household.Interview_Day_Schedule__c = slot.Id;
            update household;
        }
    }

    @IsTest
    static void zeroItemAnswerReturnsCommittedSnapshot() {
        Case application = getCase();
        Id slotId = slotFor(application.Id);
        Test.startTest();
        Map<String, Object> saved = save(slotId, form('Do Not Recommend', ''), false);
        Map<String, Object> reopened = InHomeInterviewMobileController.loadInterview(application.Id);
        Test.stopTest();
        Map<String, Object> snapshot = (Map<String, Object>)saved.get('interview');
        System.assertEquals(true, saved.get('success'));
        System.assertEquals(3, saved.get('persistenceVersion'));
        System.assertEquals('Do Not Recommend', saved.get('persistedHouseholdRecommendation'));
        System.assertEquals('Do Not Recommend', snapshot.get('householdRecommendation'));
        System.assertEquals('Do Not Recommend', reopened.get('householdRecommendation'));
        System.assertEquals('Do Not Recommend', getCase().get(ANSWER_FIELD));
        System.assertEquals(0, [SELECT COUNT() FROM pmdm__ServiceDelivery__c WHERE Case__c = :application.Id]);
    }

    @IsTest
    static void newSelectionReplacesSavedAnswer() {
        Id slotId = slotFor(getCase().Id);
        Test.startTest();
        save(slotId, form('Recommend', ''), false);
        Map<String, Object> saved = save(slotId, form('Concerns', 'Recommend'), false);
        Test.stopTest();
        System.assertEquals('Concerns', saved.get('persistedHouseholdRecommendation'));
        System.assertEquals('Concerns', getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void staleBlankDraftCannotClearNewAnswer() {
        Id slotId = slotFor(getCase().Id);
        Boolean rejected = false;
        Test.startTest();
        save(slotId, form('Strongly Recommend', ''), false);
        try {
            save(slotId, form('', ''), false);
        } catch(AuraHandledException ex) {
            rejected = true;
        }
        Test.stopTest();
        System.assert(rejected, 'An older blank draft must not erase the newer saved answer.');
        System.assertEquals('Strongly Recommend', getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void staleBaselineAllowsSameAnswer() {
        Id slotId = slotFor(getCase().Id);
        Test.startTest();
        save(slotId, form('Recommend', ''), false);
        Map<String, Object> second = save(slotId, form('Recommend', ''), false);
        Test.stopTest();
        System.assertEquals(true, second.get('success'));
        System.assertEquals('Recommend', getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void legacyEnvelopeWithoutAnswerPreservesValue() {
        Id slotId = slotFor(getCase().Id);
        Test.startTest();
        save(slotId, form('Concerns', ''), false);
        Map<String, Object> saved = InHomeInterviewMobileController.saveInterview(
            slotId, '[]', '{"__form2026":{"version":2,"otherBedNeeds":"","removedItems":[]}}',
            '', '', null, false);
        Test.stopTest();
        System.assertEquals('Concerns', saved.get('persistedHouseholdRecommendation'));
        System.assertEquals('Concerns', getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void legacySaveSignatureStillWorks() {
        Id slotId = slotFor(getCase().Id);
        Test.startTest();
        save(slotId, form('Recommend', ''), false);
        Map<String, Object> saved = InHomeInterviewMobileController.saveInterview(
            slotId, '[]', '{}', 'Review explanation', 'Review concern', null, false);
        Test.stopTest();
        Map<String, Object> snapshot = (Map<String, Object>)saved.get('interview');
        System.assertEquals('Recommend', snapshot.get('householdRecommendation'));
        System.assertEquals('Review explanation', snapshot.get('whyHelp'));
        System.assertEquals('Review concern', snapshot.get('whyNotHelp'));
    }

    @IsTest
    static void blankNewDraftDoesNotDefaultAnswer() {
        Id slotId = slotFor(getCase().Id);
        Test.startTest();
        Map<String, Object> saved = save(slotId, form('', ''), false);
        Test.stopTest();
        System.assertEquals('', saved.get('persistedHouseholdRecommendation'));
        System.assertEquals(null, getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void invalidValueRollsBackInterviewSave() {
        Id slotId = slotFor(getCase().Id);
        Boolean rejected = false;
        Test.startTest();
        try {
            save(slotId, form('Unsupported answer', ''), false);
        } catch(AuraHandledException ex) {
            rejected = true;
        }
        Test.stopTest();
        System.assert(rejected);
        System.assertEquals(null, getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void completionRequiresRecommendation() {
        Id slotId = slotFor(getCase().Id);
        Boolean rejected = false;
        Test.startTest();
        try {
            save(slotId, form('', ''), true);
        } catch(AuraHandledException ex) {
            rejected = true;
        }
        Test.stopTest();
        System.assert(rejected);
        System.assertNotEquals('Completed', [SELECT Assignment_Status__c FROM Interview_Day_Schedule__c WHERE Id = :slotId].Assignment_Status__c);
    }

    @IsTest
    static void completedSnapshotIsReadOnly() {
        Id slotId = slotFor(getCase().Id);
        Test.setMock(HttpCalloutMock.class, new CalendarMock());
        Test.startTest();
        Map<String, Object> saved = save(slotId, form('Recommend', ''), true);
        Test.stopTest();
        Map<String, Object> snapshot = (Map<String, Object>)saved.get('interview');
        System.assertEquals(true, snapshot.get('readOnly'));
        System.assertEquals('Completed', snapshot.get('assignmentStatus'));
        System.assertEquals('Recommend', snapshot.get('householdRecommendation'));
    }

    @IsTest
    static void reviewNarrativesNotDuplicatedInCaseNotes() {
        Case application = getCase();
        Id slotId = slotFor(application.Id);
        ContentNote note = new ContentNote(Title = 'Questions', Content = Blob.valueOf('<p>Confirm the household details.</p>'));
        insert note;
        insert new ContentDocumentLink(ContentDocumentId = note.Id, LinkedEntityId = application.Id, ShareType = 'V');
        Test.startTest();
        Map<String, Object> saved = InHomeInterviewMobileController.saveInterview(
            slotId, '[]', JSON.serialize(new Map<String, Object>{'__form2026' => form('Recommend', '')}),
            'Retain this positive narrative.', 'Retain this concern.', null, false);
        Test.stopTest();
        Map<String, Object> snapshot = (Map<String, Object>)saved.get('interview');
        System.assertEquals('Retain this positive narrative.', snapshot.get('whyHelp'));
        System.assertEquals('Retain this concern.', snapshot.get('whyNotHelp'));
        Boolean foundQuestion = false;
        for(Map<String, Object> item : (List<Map<String, Object>>)snapshot.get('caseNotes')) {
            System.assertNotEquals('Why We Should Help', item.get('label'));
            System.assertNotEquals('Why We Should Not Help', item.get('label'));
            if(item.get('label') == 'Questions') foundQuestion = true;
        }
        System.assert(foundQuestion, 'Actual Enhanced Notes must still be returned.');
    }

    @IsTest
    static void noScheduleSnapshotHasCurrentContract() {
        Case application = new Case(Subject = 'HGH R3 Unscheduled', Status = firstActive(Case.Status), Origin = firstActive(Case.Origin));
        application.put(ANSWER_FIELD, 'Neutral');
        insert application;
        Test.startTest();
        Map<String, Object> snapshot = InHomeInterviewMobileController.loadInterview(application.Id);
        Test.stopTest();
        System.assertEquals(3, snapshot.get('persistenceVersion'));
        System.assertEquals('Neutral', snapshot.get('persistedHouseholdRecommendation'));
        System.assertEquals(true, snapshot.get('readOnly'));
    }

    @IsTest
    static void legacyItemCreateUpdateAndNotes() {
        Id caseId = getCase().Id;
        Id slotId = slotFor(caseId);
        pmdm__Service__c service = catalogService(createProgram(), 'Pillows');
        Map<String, Object> row = new Map<String, Object>{'serviceId' => service.Id, 'quantity' => 2, 'recommendation' => ''};
        Test.startTest();
        InHomeInterviewMobileController.saveInterview(slotId, JSON.serialize(new List<Object>{row}),
            '{"linens":"Pillow notes"}', 'Needs help', 'No other concern', null, false);
        pmdm__ServiceDelivery__c first = deliveryRows(caseId)[0];
        System.assertEquals('Neutral', first.Volunteer_Recommendation__c);
        row.put('id', first.Id);
        row.put('quantity', 3);
        row.put('recommendation', 'Concerns');
        Map<String, Object> saved = InHomeInterviewMobileController.saveInterview(slotId,
            JSON.serialize(new List<Object>{row}), '{"linens":"Updated pillow notes"}',
            'Updated narrative', 'Updated concern', null, false);
        Test.stopTest();
        pmdm__ServiceDelivery__c actual = deliveryRows(caseId)[0];
        System.assertEquals(first.Id, actual.Id);
        System.assertEquals(Decimal.valueOf('3'), actual.Quantity__c);
        System.assertEquals('Concerns', actual.Volunteer_Recommendation__c);
        System.assertEquals('Updated pillow notes', actual.Notes__c);
        System.assertEquals('Updated narrative', ((Map<String, Object>)saved.get('interview')).get('whyHelp'));
    }

    @IsTest
    static void formCreatesItemsAcrossAllSections() {
        Id caseId = getCase().Id;
        Id slotId = slotFor(caseId);
        createProgram();
        List<Object> items = new List<Object>{
            requestItem('bed', 'Beds', 'Twin', 'Male', '', 2),
            requestItem('bedding', 'Bedding', 'Full', 'Female', '', 1),
            requestItem('mattress', 'Mattress Only', 'Queen', '', '', 1),
            requestItem('frame', 'Bed Frame Only', 'King', '', '', 1),
            requestItem('pillow', 'Pillows', '', '', '', 2),
            requestItem('towel', 'Towels', '', '', '', 2),
            requestItem('washcloth', 'Washcloths', '', '', '', 2),
            requestItem('appliance', 'Small Appliance', 'Other', '', 'Electric kettle', 1),
            requestItem('furniture', 'Furniture', 'Other', '', 'Storage bench', 1)
        };
        Map<String, Object> envelope = form('Recommend', '');
        envelope.put('otherBedNeeds', 'Additional bed rail');
        Test.startTest();
        Map<String, Object> saved = saveItems(slotId, items, envelope);
        Test.stopTest();
        System.assertEquals(9, ((Map<String, Id>)saved.get('savedItemIds')).size());
        List<pmdm__ServiceDelivery__c> actual = deliveryRows(caseId);
        System.assertEquals(9, actual.size());
        Integer noteOwners = 0;
        for(pmdm__ServiceDelivery__c item : actual) {
            System.assertEquals('Recommend', item.Volunteer_Recommendation__c);
            if(String.isNotBlank(item.Other_Bed_Needs__c)) noteOwners++;
        }
        System.assertEquals(1, noteOwners);
        Map<String, Object> snapshot = (Map<String, Object>)saved.get('interview');
        System.assertEquals('Additional bed rail', snapshot.get('otherBedNeeds'));
        Set<String> sections = new Set<String>();
        for(Map<String, Object> item : (List<Map<String, Object>>)snapshot.get('items')) {
            sections.add((String)item.get('sectionKey'));
        }
        System.assert(sections.containsAll(new Set<String>{'newBeds','existingBedding','linens','smallAppliances','furniture'}));
    }

    @IsTest
    static void formReusesUnlinkedItemThenReclassifiesWithoutChangingCatalog() {
        Id caseId = getCase().Id;
        Id slotId = slotFor(caseId);
        pmdm__Service__c service = catalogService(createProgram(), 'Pillows');
        pmdm__ServiceDelivery__c existing = makeDelivery(caseId, null, service.Id);
        Map<String, Object> row = requestItem('existing', '', '', '', '', 2);
        row.put('id', existing.Id);
        row.put('serviceId', service.Id);
        row.put('section', 'linens');
        Test.startTest();
        saveItems(slotId, new List<Object>{row}, form('Recommend', ''));
        System.assertEquals(service.Id, deliveryRows(caseId)[0].pmdm__Service__c);
        row.put('category', 'Towels');
        row.put('quantity', 3);
        saveItems(slotId, new List<Object>{row}, form('Concerns', 'Recommend'));
        Test.stopTest();
        pmdm__ServiceDelivery__c actual = deliveryRows(caseId)[0];
        System.assertEquals(existing.Id, actual.Id);
        System.assertEquals(slotId, actual.Interview_Day_Schedule__c);
        System.assertNotEquals(service.Id, actual.pmdm__Service__c);
        System.assertEquals('Towels', actual.pmdm__Service__r.Category__c);
        System.assertEquals('Pillows', [SELECT Category__c FROM pmdm__Service__c WHERE Id = :service.Id].Category__c);
        System.assertEquals(Decimal.valueOf('3'), actual.Quantity__c);
    }

    @IsTest
    static void deleteOnlyRequestedInterviewItems() {
        Id caseId = getCase().Id;
        Id slotId = slotFor(caseId);
        pmdm__Service__c service = catalogService(createProgram(), 'Pillows');
        pmdm__ServiceDelivery__c remove = makeDelivery(caseId, slotId, service.Id);
        pmdm__ServiceDelivery__c keep = makeDelivery(caseId, slotId, service.Id);
        Map<String, Object> keptItem = requestItem('keep', 'Pillows', '', '', '', 1);
        keptItem.put('id', keep.Id);
        keptItem.put('serviceId', service.Id);
        Map<String, Object> envelope = form('Neutral', '');
        envelope.put('removedItems', new List<Object>{new Map<String, Object>{'id' => remove.Id},
            new Map<String, Object>{'id' => remove.Id}, new Map<String, Object>()});
        Test.startTest();
        saveItems(slotId, new List<Object>{keptItem}, envelope);
        Test.stopTest();
        List<pmdm__ServiceDelivery__c> remaining = deliveryRows(caseId);
        System.assertEquals(1, remaining.size());
        System.assertEquals(keep.Id, remaining[0].Id);
    }

    @IsTest
    static void reviewedItemCanRemainButCannotChangeOrBeDeleted() {
        Id caseId = getCase().Id;
        Id slotId = slotFor(caseId);
        pmdm__Service__c service = catalogService(createProgram(), 'Pillows');
        pmdm__ServiceDelivery__c delivery = makeDelivery(caseId, slotId, service.Id);
        update new pmdm__ServiceDelivery__c(Id = delivery.Id, HGH_Approval_Reviewed_On__c = System.now());
        Map<String, Object> row = requestItem('locked', 'Pillows', '', '', '', 1);
        row.put('id', delivery.Id);
        row.put('serviceId', service.Id);
        Test.startTest();
        Map<String, Object> saved = saveItems(slotId, new List<Object>{row}, form('Neutral', ''));
        row.put('quantity', 2);
        Boolean changeRejected = false;
        try { saveItems(slotId, new List<Object>{row}, form('Neutral', 'Neutral')); }
        catch(AuraHandledException ex) { changeRejected = true; }
        Map<String, Object> removal = form('Neutral', 'Neutral');
        removal.put('removedItems', new List<Object>{new Map<String, Object>{'id' => delivery.Id}});
        Boolean deleteRejected = false;
        try { saveItems(slotId, new List<Object>(), removal); }
        catch(AuraHandledException ex) { deleteRejected = true; }
        Test.stopTest();
        System.assertEquals(delivery.Id, ((Map<String, Id>)saved.get('savedItemIds')).get('locked'));
        System.assert(changeRejected && deleteRejected);
        System.assertEquals(Decimal.valueOf('1'), deliveryRows(caseId)[0].Quantity__c);
    }

    @IsTest
    static void malformedPayloadsAndTooManyItemsAreRejected() {
        Id slotId = slotFor(getCase().Id);
        List<Object> tooMany = new List<Object>();
        for(Integer i = 0; i < 151; i++) tooMany.add(requestItem('many-' + i, 'Pillows', '', '', '', 1));
        String notes = JSON.serialize(new Map<String, Object>{'__form2026' => form('Neutral', '')});
        Test.startTest();
        expectFailure(slotId, '[]', '{invalid-json');
        expectFailure(slotId, '{invalid-json', notes);
        expectFailure(slotId, JSON.serialize(tooMany), notes);
        Test.stopTest();
        System.assertEquals(null, getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void categoryGenderAndOtherTextAreValidated() {
        Id slotId = slotFor(getCase().Id);
        String notes = JSON.serialize(new Map<String, Object>{'__form2026' => form('Neutral', '')});
        List<Object> invalidItems = new List<Object>{
            requestItem('bad-category', 'Unknown Category', '', '', '', 1),
            requestItem('no-gender', 'Beds', 'Twin', '', '', 1),
            requestItem('missing-other', 'Furniture', 'Other', '', '', 1)
        };
        Test.startTest();
        for(Object item : invalidItems) expectFailure(slotId, JSON.serialize(new List<Object>{item}), notes);
        Test.stopTest();
        System.assertEquals(null, getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void fractionsAndBedNotesWithoutItemsAreRejected() {
        Id slotId = slotFor(getCase().Id);
        String notes = JSON.serialize(new Map<String, Object>{'__form2026' => form('Neutral', '')});
        Map<String, Object> bedNotes = form('Neutral', '');
        bedNotes.put('otherBedNeeds', 'A bed note without an item');
        Test.startTest();
        expectFailure(slotId, JSON.serialize(new List<Object>{requestItem('fraction', 'Pillows', '', '', '', 1.5)}), notes);
        expectFailure(slotId, '[]', JSON.serialize(new Map<String, Object>{'__form2026' => bedNotes}));
        Test.stopTest();
        System.assertEquals(null, getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void historicalCommonAndMixedRecommendationsStillLoad() {
        Id caseId = getCase().Id;
        Id slotId = slotFor(caseId);
        pmdm__Service__c service = catalogService(createProgram(), 'Pillows');
        pmdm__ServiceDelivery__c one = makeDelivery(caseId, slotId, service.Id);
        makeDelivery(caseId, slotId, service.Id);
        Test.startTest();
        Map<String, Object> common = InHomeInterviewMobileController.loadInterview(slotId);
        update new pmdm__ServiceDelivery__c(Id = one.Id, Volunteer_Recommendation__c = 'Concerns');
        Map<String, Object> mixed = InHomeInterviewMobileController.loadInterview(slotId);
        Test.stopTest();
        System.assertEquals('Neutral', common.get('householdRecommendation'));
        System.assertEquals('', common.get('persistedHouseholdRecommendation'));
        System.assertEquals('', mixed.get('householdRecommendation'));
        System.assertEquals(null, getCase().get(ANSWER_FIELD));
    }

    @IsTest
    static void assignedListAndLifecycleRemainAvailable() {
        Id slotId = slotFor(getCase().Id);
        InHomeInterviewMobileController.systemAdministratorOverride = false;
        InHomeInterviewMobileController.currentUserIdOverride = UserInfo.getUserId();
        Test.startTest();
        List<Map<String, Object>> beforeRows = InHomeInterviewMobileController.loadAssignedInterviews();
        save(slotId, form('Recommend', ''), false);
        List<Map<String, Object>> afterRows = InHomeInterviewMobileController.loadAssignedInterviews();
        Test.stopTest();
        System.assertEquals('Start Interview', findAssigned(beforeRows, slotId).get('actionLabel'));
        System.assertEquals('Resume', findAssigned(afterRows, slotId).get('actionLabel'));
    }

    private static Map<String, Object> findAssigned(List<Map<String, Object>> rows, Id slotId) {
        for(Map<String, Object> row : rows) if((Id)row.get('scheduleId') == slotId) return row;
        System.assert(false, 'Assigned test interview was not returned.');
        return null;
    }

    private static void expectFailure(Id slotId, String items, String notes) {
        Boolean rejected = false;
        try { InHomeInterviewMobileController.saveInterview(slotId, items, notes, '', '', null, false); }
        catch(AuraHandledException ex) { rejected = true; }
        System.assert(rejected, 'Invalid requests must be rejected rather than silently saved.');
    }

    private static Id createProgram() {
        pmdm__Program__c program = new pmdm__Program__c(Name = 'HGH R3 Program ' + Date.today().year(), pmdm__status__c = 'Active');
        insert program;
        return program.Id;
    }

    private static pmdm__Service__c catalogService(Id programId, String category) {
        pmdm__Service__c service = new pmdm__Service__c(Name = 'HGH R3 ' + category, pmdm__Program__c = programId, Category__c = category);
        insert service;
        return service;
    }

    private static pmdm__ServiceDelivery__c makeDelivery(Id caseId, Id slotId, Id serviceId) {
        pmdm__ServiceDelivery__c delivery = new pmdm__ServiceDelivery__c(Name = 'HGH R3 Item', Case__c = caseId,
            Interview_Day_Schedule__c = slotId, pmdm__Service__c = serviceId,
            Quantity__c = 1, Status__c = 'Requested', Volunteer_Recommendation__c = 'Neutral');
        insert delivery;
        return delivery;
    }

    private static List<pmdm__ServiceDelivery__c> deliveryRows(Id caseId) {
        return [SELECT Id, pmdm__Service__c, pmdm__Service__r.Category__c, Quantity__c, Status__c,
            Volunteer_Recommendation__c, Notes__c, Other_Bed_Needs__c, Interview_Day_Schedule__c
            FROM pmdm__ServiceDelivery__c WHERE Case__c = :caseId ORDER BY CreatedDate, Id];
    }

    private static Map<String, Object> requestItem(String key, String category, String subcategory, String gender, String customEntry, Decimal quantity) {
        return new Map<String, Object>{'clientKey' => key, 'category' => category, 'subcategory' => subcategory,
            'gender' => gender, 'customEntry' => customEntry, 'quantity' => quantity, 'recommendation' => 'Neutral', 'section' => ''};
    }

    private static Map<String, Object> saveItems(Id slotId, List<Object> items, Map<String, Object> envelope) {
        return InHomeInterviewMobileController.saveInterview(slotId, JSON.serialize(items),
            JSON.serialize(new Map<String, Object>{'linens' => 'Test linen notes', '__form2026' => envelope}), '', '', null, false);
    }

    private static Map<String, Object> form(String answer, String expected) {
        return new Map<String, Object>{'version' => 3, 'householdRecommendation' => answer,
            'expectedRecommendation' => expected, 'otherBedNeeds' => '', 'removedItems' => new List<Object>()};
    }

    private static Map<String, Object> save(Id slotId, Map<String, Object> envelope, Boolean completeInterview) {
        return InHomeInterviewMobileController.saveInterview(slotId, '[]',
            JSON.serialize(new Map<String, Object>{'__form2026' => envelope}), '', '', null, completeInterview);
    }

    private static Case getCase() {
        return (Case)Database.query('SELECT Id, AccountId, ' + ANSWER_FIELD + ' FROM Case WHERE Subject = :SUBJECT LIMIT 1');
    }

    private static Id slotFor(Id caseId) {
        return [SELECT Id FROM Interview_Day_Schedule__c WHERE Case__c = :caseId AND Booked__c = true LIMIT 1].Id;
    }

    private static String firstActive(Schema.SObjectField token) {
        for(Schema.PicklistEntry entry : token.getDescribe().getPicklistValues()) {
            if(entry.isActive()) return entry.getValue();
        }
        return null;
    }

    private class CalendarMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"id":"hgh-test-event","status":"confirmed"}');
            return response;
        }
    }
}