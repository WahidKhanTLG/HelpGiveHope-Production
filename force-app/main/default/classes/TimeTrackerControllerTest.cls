@isTest
private class TimeTrackerControllerTest {
    @testSetup
    static void setup() {
        // Base contact used by several tests
        insert new Contact(
            LastName = 'Test Contact',
            Email = 'test@example.com',
            Phone = '1234567890'
        );

        // Extra contacts to exercise getTodaysEntries()
        List<Contact> extraContacts = new List<Contact>{
            new Contact(LastName='Alice',  Email='alice@example.com',  Phone='1111111111'),
            new Contact(LastName='Bob',    Email='bob@example.com',    Phone='2222222222'),
            new Contact(LastName='Carol',  Email='carol@example.com',  Phone='3333333333'),
            new Contact(LastName='Dan',    Email='dan@example.com',    Phone='4444444444'),
            new Contact(LastName='Eve',    Email='eve@example.com',    Phone='5555555555')
        };
        insert extraContacts;

        // Helper to make datetimes at specific times
        Date today = Date.today();
        Date yesterday = today.addDays(-1);
        Date tomorrow  = today.addDays(1);

        // Closed entry fully inside today (2 hours) -> expect 2.0 hours
        insert new Time_Entry__c(
            Contact__c = [SELECT Id FROM Contact WHERE Email = 'alice@example.com' LIMIT 1].Id,
            Start_Time__c = Datetime.newInstance(today, Time.newInstance(9, 0, 0, 0)),
            End_Time__c   = Datetime.newInstance(today, Time.newInstance(11, 0, 0, 0))
        );

        // Open entry that started today morning -> clip to now
        insert new Time_Entry__c(
            Contact__c = [SELECT Id FROM Contact WHERE Email = 'bob@example.com' LIMIT 1].Id,
            Start_Time__c = Datetime.newInstance(today, Time.newInstance(8, 30, 0, 0))
        );

        // Spans midnight: yesterday 23:00 to today 02:00 -> expect 2.0 hours inside today
        insert new Time_Entry__c(
            Contact__c = [SELECT Id FROM Contact WHERE Email = 'carol@example.com' LIMIT 1].Id,
            Start_Time__c = Datetime.newInstance(yesterday, Time.newInstance(23, 0, 0, 0)),
            End_Time__c   = Datetime.newInstance(today,     Time.newInstance(2, 0, 0, 0))
        );

        // Entirely before today -> should NOT appear
        insert new Time_Entry__c(
            Contact__c = [SELECT Id FROM Contact WHERE Email = 'dan@example.com' LIMIT 1].Id,
            Start_Time__c = Datetime.newInstance(yesterday, Time.newInstance(10, 0, 0, 0)),
            End_Time__c   = Datetime.newInstance(yesterday, Time.newInstance(12, 0, 0, 0))
        );

        // Entirely in the future (tomorrow) -> should NOT appear
        insert new Time_Entry__c(
            Contact__c = [SELECT Id FROM Contact WHERE Email = 'eve@example.com' LIMIT 1].Id,
            Start_Time__c = Datetime.newInstance(tomorrow, Time.newInstance(9, 0, 0, 0)),
            End_Time__c   = Datetime.newInstance(tomorrow, Time.newInstance(10, 0, 0, 0))
        );

        // Zero-duration entry today -> included but totalHours = null
        insert new Time_Entry__c(
            Contact__c = [SELECT Id FROM Contact WHERE Email = 'alice@example.com' LIMIT 1].Id,
            Start_Time__c = Datetime.newInstance(today, Time.newInstance(12, 0, 0, 0)),
            End_Time__c   = Datetime.newInstance(today, Time.newInstance(12, 0, 0, 0))
        );
    }

    @isTest
    static void testCheckTimeEntryStatus_NoContactFound() {
        Test.startTest();
        String result = TimeTrackerController.checkTimeEntryStatus('0000000000');
        Test.stopTest();
        System.assertEquals('No contact found for the provided Phone or Email.::Error', result);
    }

    @isTest
    static void testCheckTimeEntryStatus_NoActiveCheckIn() {
        Contact c = [SELECT Id, Email FROM Contact WHERE Email = 'test@example.com' LIMIT 1];
        Test.startTest();
        String result = TimeTrackerController.checkTimeEntryStatus(c.Email);
        Test.stopTest();
        System.assertEquals('No active check-in::Success', result);
    }

    @isTest
    static void testCheckTimeEntryStatus_CheckedIn() {
        Contact c = [SELECT Id, Email FROM Contact WHERE Email = 'test@example.com' LIMIT 1];
        insert new Time_Entry__c(Contact__c = c.Id, Start_Time__c = Datetime.now());
        Test.startTest();
        String result = TimeTrackerController.checkTimeEntryStatus(c.Email);
        Test.stopTest();
        System.assertEquals('Checked in::Success', result);
    }

    @isTest
    static void testCreateTimeEntry_CheckIn_ByEmail() {
        Contact c = [SELECT Id, Email FROM Contact WHERE Email = 'test@example.com' LIMIT 1];
        Test.startTest();
        String result = TimeTrackerController.createTimeEntry(c.Email);
        Test.stopTest();
        System.assert(result.contains('has been checked in.::Success'));
        Time_Entry__c te = [SELECT Id, Start_Time__c, End_Time__c FROM Time_Entry__c WHERE Contact__c = :c.Id ORDER BY CreatedDate DESC LIMIT 1];
        System.assertNotEquals(null, te.Start_Time__c);
        System.assertEquals(null, te.End_Time__c);
    }

    @isTest
    static void testCreateTimeEntry_CheckIn_ByPhone() {
        Contact c = [SELECT Id, Phone FROM Contact WHERE Email = 'test@example.com' LIMIT 1];
        Test.startTest();
        String result = TimeTrackerController.createTimeEntry(c.Phone);
        Test.stopTest();
        System.assert(result.contains('has been checked in.::Success'));
    }

    @isTest
    static void testCreateTimeEntry_CheckOut_UpsertsSameRecord() {
        Contact c = [SELECT Id, Email, Name FROM Contact WHERE Email = 'test@example.com' LIMIT 1];

        // First call: check in
        String res1 = TimeTrackerController.createTimeEntry(c.Email);
        System.assert(res1.contains('checked in'));

        // Count entries before checkout
        Integer beforeCount = [SELECT COUNT() FROM Time_Entry__c WHERE Contact__c = :c.Id];

        Test.startTest();
        String res2 = TimeTrackerController.createTimeEntry(c.Email); // Now should check out (update existing)
        Test.stopTest();

        System.assert(res2.contains('checked out'));
        Integer afterCount = [SELECT COUNT() FROM Time_Entry__c WHERE Contact__c = :c.Id];
        System.assertEquals(beforeCount, afterCount, 'Checkout should update same record (upsert on Id).');

        Time_Entry__c updated = [SELECT Id, Start_Time__c, End_Time__c, Name FROM Time_Entry__c WHERE Contact__c = :c.Id ORDER BY CreatedDate DESC LIMIT 1];
        System.assertNotEquals(null, updated.Start_Time__c);
        System.assertNotEquals(null, updated.End_Time__c);
        System.assert(updated.Name.startsWith(c.Name + ' - '), 'Name should contain contact and date.');
    }

    @isTest
    static void testGetTodaysEntries_MixedOverlap() {
        Test.startTest();
        List<TimeTrackerController.TimeEntryRow> rows = TimeTrackerController.getTodaysEntries();
        Test.stopTest();

        // Build a map by contact name for easy assertions
        Map<String, TimeTrackerController.TimeEntryRow> byName = new Map<String, TimeTrackerController.TimeEntryRow>();
        for (TimeTrackerController.TimeEntryRow r : rows) {
            if (r.contactName != null && !byName.containsKey(r.contactName)) {
                byName.put(r.contactName, r);
            }
        }

        System.assert(byName.containsKey('Alice'), 'Alice (closed 2h + zero-duration) should be present.');
        System.assert(byName.containsKey('Bob'),   'Bob (open today) should be present.');
        System.assert(byName.containsKey('Carol'), 'Carol (spans midnight) should be present.');
        System.assert(!byName.containsKey('Dan'),  'Dan (yesterday only) should be excluded.');
        System.assert(!byName.containsKey('Eve'),  'Eve (tomorrow only) should be excluded.');

        // Alice: the most recent row may be the zero-duration one (12:00->12:00) due to ORDER BY Start DESC,
        // which should yield totalHours = null (clipped duration <= 0).
        TimeTrackerController.TimeEntryRow aliceRow = byName.get('Alice');
        System.assertEquals(null, aliceRow.totalHours, 'Zero-duration entry should set totalHours to null.');

        // Carol (yesterday 23:00 to today 02:00): clipped to 00:00-02:00 = 2 hours
        TimeTrackerController.TimeEntryRow carolRow = byName.get('Carol');
        System.assertNotEquals(null, carolRow.totalHours);
        System.assertEquals(2, carolRow.totalHours.intValue(), 'Carol should count as 2 hours inside today.');

        // Bob: open from 08:30 -> clipped to now; just assert positive and not null
        TimeTrackerController.TimeEntryRow bobRow = byName.get('Bob');
        System.assertNotEquals(null, bobRow.totalHours, 'Open entry should compute a duration.');
        System.assert(bobRow.totalHours > 0, 'Open entry should have a positive duration.');

        // Spot-check fields presence
        System.assertNotEquals(null, bobRow.entryId);
        System.assertNotEquals(null, bobRow.contactId);
        System.assertNotEquals(null, bobRow.startTime);
        // bobRow.endTime should be null (open)
        System.assertEquals(null, bobRow.endTime);
    }

    @isTest
    static void testGetTodaysEntries_ReturnsMax500NoCrash() {
        // Insert many entries touching today to ensure query limit works but does not crash
        List<Contact> contacts = new List<Contact>();
        for (Integer i=0; i<20; i++) {
            contacts.add(new Contact(LastName='Bulk'+i, Email='bulk'+i+'@example.com'));
        }
        insert contacts;

        List<Time_Entry__c> many = new List<Time_Entry__c>();
        Date today = Date.today();
        for (Contact c : contacts) {
            many.add(new Time_Entry__c(
                Contact__c = c.Id,
                Start_Time__c = Datetime.newInstance(today, Time.newInstance(6, 0, 0, 0)),
                End_Time__c   = Datetime.newInstance(today, Time.newInstance(7, 0, 0, 0))
            ));
        }
        insert many;

        Test.startTest();
        List<TimeTrackerController.TimeEntryRow> rows = TimeTrackerController.getTodaysEntries();
        Test.stopTest();

        // At least the 20 we just added should be present somewhere
        Integer countBulk = 0;
        for (TimeTrackerController.TimeEntryRow r : rows) {
            if (r.contactName != null && r.contactName.startsWith('Bulk')) countBulk++;
        }
        System.assert(countBulk == 20, 'Should include all newly inserted today-touching entries.');
    }
}