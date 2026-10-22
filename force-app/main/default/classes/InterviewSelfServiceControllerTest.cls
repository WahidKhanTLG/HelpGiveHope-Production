@IsTest
private class InterviewSelfServiceControllerTest {

    private static final String TRACT = '83.01';

    @TestSetup
    static void setup() {
        Zone__c zone = InterviewSchedulingTestData.createZone('Self Service Zone', TRACT, 'Afternoon');
        InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(10), 'AfterNoon', 3, 'Published');
        InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(11), 'AfterNoon', 2, 'Planned');

        Account household = InterviewSchedulingTestData.createHousehold('Self Service Household', TRACT);
        Contact contact = InterviewSchedulingTestData.createContact(household, 'Grace', 'grace@example.org');
        InterviewSchedulingTestData.createApplication(household, contact);
    }

    private static String issueToken(Integer cutoff, Integer maxReschedules) {
        InterviewSchedulingTestData.googleSettings(true);
        InterviewSchedulingTestData.selfServiceConfig(cutoff, maxReschedules);
        Case app = [SELECT Id FROM Case LIMIT 1];
        return InterviewSelfServiceService.generateAndStore(app.Id).token;
    }

    @IsTest
    static void validTokenReturnsOpenSlotsAndFirstNameOnly() {
        String token = issueToken(24, 3);

        Test.startTest();
        InterviewSelfServiceController.BookingDTO dto = InterviewSelfServiceController.getBooking(token);
        Test.stopTest();

        System.assertEquals('OK', dto.status, '' + dto.message);
        System.assertEquals('Grace', dto.firstName);
        System.assertEquals(false, dto.hasBooking);
        System.assertEquals(true, dto.canChange);
        System.assertEquals(24, dto.cutoffHours);
        System.assertEquals('555-0100', dto.supportPhone);
        System.assertEquals(1, dto.days.size(), 'Only the Published day is offered');
        System.assertEquals('Afternoon', dto.days[0].mode, 'AfterNoon is normalised for display');
        System.assertEquals(3, dto.days[0].slots.size());
        System.assertEquals('12:30 PM - 12:45 PM', dto.days[0].slots[0].label, 'Afternoon slots start at 12:30');
        System.assertEquals(true, dto.days[0].slots[0].selectable);
    }

    @IsTest
    static void invalidExpiredAndDisabledTokensAreRejected() {
        String token = issueToken(24, 3);

        System.assertEquals('INVALID', InterviewSelfServiceController.getBooking('not-a-token').status);
        System.assertEquals('INVALID', InterviewSelfServiceController.getBooking(null).status);
        System.assertEquals('INVALID', InterviewSelfServiceController.getBooking(InterviewSelfServiceService.generateToken()).status,
            'A well-formed token that was never issued is rejected');

        Case app = [SELECT Id FROM Case LIMIT 1];
        update new Case(Id = app.Id, Self_Service_Token_Expires__c = System.now().addMinutes(-1));
        System.assertEquals('EXPIRED', InterviewSelfServiceController.getBooking(token).status);

        update new Case(Id = app.Id, Self_Service_Token_Expires__c = System.now().addDays(1));
        InterviewSelfServiceConfig.instanceOverride.enabled = false;
        System.assertEquals('DISABLED', InterviewSelfServiceController.getBooking(token).status);
    }

    @IsTest
    static void selectSlotBooksThenReschedulesAndCountsChanges() {
        String token = issueToken(24, 2);
        Case app = [SELECT Id, AccountId FROM Case LIMIT 1];
        Interview_Day__c day = [SELECT Id FROM Interview_Day__c WHERE Status__c = 'Published' LIMIT 1];
        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day.Id);

        Test.startTest();
        InterviewSelfServiceController.BookingDTO first = InterviewSelfServiceController.selectSlot(token, slots[0].Id);
        System.assertEquals('OK', first.status, '' + first.message);
        System.assertEquals(true, first.hasBooking);
        System.assertEquals(slots[0].Id, first.currentScheduleId);
        System.assertEquals('12:30 PM - 12:45 PM', first.currentTimeLabel);
        System.assertEquals(2, first.reschedulesRemaining, 'A first booking is not a reschedule');
        System.assertEquals(2, first.days[0].slots.size(), 'Booked slot disappears from the open list');

        InterviewSelfServiceController.BookingDTO second = InterviewSelfServiceController.selectSlot(token, slots[1].Id);
        System.assertEquals('OK', second.status, '' + second.message);
        System.assertEquals(slots[1].Id, second.currentScheduleId);
        System.assertEquals(1, second.reschedulesRemaining);

        InterviewSelfServiceController.BookingDTO third = InterviewSelfServiceController.selectSlot(token, slots[2].Id);
        System.assertEquals('OK', third.status, '' + third.message);
        System.assertEquals(0, third.reschedulesRemaining);
        System.assertEquals(false, third.canChange, 'Limit reached: no more online changes');

        InterviewSelfServiceController.BookingDTO fourth = InterviewSelfServiceController.selectSlot(token, slots[0].Id);
        Test.stopTest();

        System.assertEquals('ERROR', fourth.status);
        System.assert(fourth.message.contains('maximum'), '' + fourth.message);
        System.assertEquals(slots[2].Id, fourth.currentScheduleId, 'Booking unchanged after the rejected attempt');

        Case updated = [SELECT Reschedule_Count__c, Self_Service_Last_Action_On__c FROM Case WHERE Id = :app.Id];
        System.assertEquals(2, updated.Reschedule_Count__c.intValue());
        System.assertNotEquals(null, updated.Self_Service_Last_Action_On__c);

        System.assertEquals(false, InterviewSchedulingTestData.slot(slots[0].Id).Booked__c, 'First slot released');
        System.assertEquals(false, InterviewSchedulingTestData.slot(slots[1].Id).Booked__c, 'Second slot released');
        System.assertEquals(true, InterviewSchedulingTestData.slot(slots[2].Id).Booked__c);
        System.assertEquals(slots[2].Id, [SELECT Interview_Day_Schedule__c FROM Case WHERE Id = :app.Id].Interview_Day_Schedule__c);
    }

    @IsTest
    static void interviewerNameIsFriendlyOrHidden() {
        System.assertEquals('Val Volunteer', InterviewSelfServiceController.interviewerName(new User(FirstName = 'Val', LastName = 'Volunteer')));
        System.assertEquals('Zurfluh', InterviewSelfServiceController.interviewerName(new User(LastName = 'Zurfluh')));
        System.assertEquals(null, InterviewSelfServiceController.interviewerName(new User(LastName = 'User1759426839263744227')), 'Auto-generated names are hidden');
        System.assertEquals(null, InterviewSelfServiceController.interviewerName(null));
    }

    @IsTest
    static void selectingTheBookedSlotAgainIsAnError() {
        String token = issueToken(24, 3);
        Interview_Day__c day = [SELECT Id FROM Interview_Day__c WHERE Status__c = 'Published' LIMIT 1];
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day.Id)[0];
        InterviewSelfServiceController.selectSlot(token, slot.Id);

        InterviewSelfServiceController.BookingDTO dto = InterviewSelfServiceController.selectSlot(token, slot.Id);

        System.assertEquals('ERROR', dto.status);
        System.assert(dto.message.contains('already the booked'), '' + dto.message);
        System.assertEquals('ERROR', InterviewSelfServiceController.selectSlot(token, null).status);
    }

    @IsTest
    static void plannedDaySlotsCannotBeChosenByApplicants() {
        String token = issueToken(24, 3);
        Interview_Day__c planned = [SELECT Id FROM Interview_Day__c WHERE Status__c = 'Planned' LIMIT 1];
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(planned.Id)[0];

        InterviewSelfServiceController.BookingDTO dto = InterviewSelfServiceController.selectSlot(token, slot.Id);

        System.assertEquals('ERROR', dto.status);
        System.assert(dto.message.contains('not open'), '' + dto.message);
        System.assertEquals(false, InterviewSchedulingTestData.slot(slot.Id).Booked__c);
    }

    @IsTest
    static void bookingWithinCutoffCannotBeChanged() {
        String token = issueToken(24, 3);
        Case app = [SELECT Id, AccountId FROM Case LIMIT 1];
        Zone__c zone = [SELECT Id FROM Zone__c LIMIT 1];
        Interview_Day__c today = InterviewSchedulingTestData.createInterviewDay(zone, Date.today(), 'AfterNoon', 1, 'Published');
        Interview_Day_Schedule__c todaySlot = InterviewSchedulingTestData.slotsFor(today.Id)[0];
        // Staff book the household into today's slot.
        InterviewBookingService.book(todaySlot.Id, app.Id, null, InterviewBookingService.Actor.STAFF);

        InterviewSelfServiceController.BookingDTO dto = InterviewSelfServiceController.getBooking(token);

        System.assertEquals('OK', dto.status);
        System.assertEquals(true, dto.hasBooking);
        System.assertEquals(false, dto.canChange);
        System.assert(dto.cannotChangeReason.contains('24 hours'), '' + dto.cannotChangeReason);
        System.assertEquals(0, dto.days.size(), 'No alternatives are offered when the change is not allowed');
    }

    @IsTest
    static void householdWithoutZoneGetsNoZoneStatus() {
        String token = issueToken(24, 3);
        Case app = [SELECT Id, AccountId FROM Case LIMIT 1];
        update new Account(Id = app.AccountId, Census_Tract__c = null);

        InterviewSelfServiceController.BookingDTO dto = InterviewSelfServiceController.getBooking(token);

        System.assertEquals('NO_ZONE', dto.status);
        System.assertEquals(false, dto.canChange);
        System.assertEquals(0, dto.days.size());
    }
}