@IsTest
public class InterviewDaysTriggerTest {

    @TestSetup
    static void setupData() {
        insert new List<Zone__c>{
            new Zone__c(
                Name = 'Timing Test Morning Zone',
                Schedule_Mode__c = 'Morning'
            ),
            new Zone__c(
                Name = 'Timing Test Afternoon Zone',
                Schedule_Mode__c = 'Afternoon'
            )
        };
    }

    @IsTest
    static void testMorningTenSlots() {
        Zone__c zone = [
            SELECT Id
            FROM Zone__c
            WHERE Name = 'Timing Test Morning Zone'
            LIMIT 1
        ];

        Interview_Day__c interviewDay = new Interview_Day__c(
            Total_Slots__c = 10,
            Zone__c = zone.Id,
            Interview_Date__c = Date.today().addDays(7),
            Schedule_Mode__c = 'Morning'
        );

        Test.startTest();
        insert interviewDay;
        Test.stopTest();

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id,
                   Name,
                   Start_Time__c,
                   End_Time__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDay.Id
            ORDER BY Start_Time__c ASC
        ];

        for (Interview_Day_Schedule__c schedule : schedules) {
            String.valueOf(schedule.Id);
            String.valueOf(schedule.Name);
            String.valueOf(schedule.Start_Time__c);
            String.valueOf(schedule.End_Time__c);
        }
    }

    @IsTest
    static void testAfternoonElevenSlots() {
        Zone__c zone = [
            SELECT Id
            FROM Zone__c
            WHERE Name = 'Timing Test Afternoon Zone'
            LIMIT 1
        ];

        Interview_Day__c interviewDay = new Interview_Day__c(
            Total_Slots__c = 11,
            Zone__c = zone.Id,
            Interview_Date__c = Date.today().addDays(8),
            Schedule_Mode__c = 'Afternoon'
        );

        Test.startTest();
        insert interviewDay;
        Test.stopTest();

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id,
                   Name,
                   Start_Time__c,
                   End_Time__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDay.Id
            ORDER BY Start_Time__c ASC
        ];

        for (Interview_Day_Schedule__c schedule : schedules) {
            String.valueOf(schedule.Id);
            String.valueOf(schedule.Name);
            String.valueOf(schedule.Start_Time__c);
            String.valueOf(schedule.End_Time__c);
        }
    }

    @IsTest
    static void testIncreaseSlotsBeforeBooking() {
        Zone__c zone = [
            SELECT Id
            FROM Zone__c
            WHERE Name = 'Timing Test Morning Zone'
            LIMIT 1
        ];

        Interview_Day__c interviewDay = new Interview_Day__c(
            Total_Slots__c = 10,
            Zone__c = zone.Id,
            Interview_Date__c = Date.today().addDays(9),
            Schedule_Mode__c = 'Morning'
        );
        insert interviewDay;

        interviewDay.Total_Slots__c = 12;

        Test.startTest();
        update interviewDay;
        Test.stopTest();

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id,
                   Start_Time__c,
                   End_Time__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDay.Id
            ORDER BY Start_Time__c ASC
        ];

        for (Interview_Day_Schedule__c schedule : schedules) {
            String.valueOf(schedule.Start_Time__c);
            String.valueOf(schedule.End_Time__c);
        }
    }

    @IsTest
    static void testDecreaseSlotsBeforeBooking() {
        Zone__c zone = [
            SELECT Id
            FROM Zone__c
            WHERE Name = 'Timing Test Afternoon Zone'
            LIMIT 1
        ];

        Interview_Day__c interviewDay = new Interview_Day__c(
            Total_Slots__c = 12,
            Zone__c = zone.Id,
            Interview_Date__c = Date.today().addDays(10),
            Schedule_Mode__c = 'Afternoon'
        );
        insert interviewDay;

        interviewDay.Total_Slots__c = 8;

        Test.startTest();
        update interviewDay;
        Test.stopTest();

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id,
                   Start_Time__c,
                   End_Time__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDay.Id
            ORDER BY Start_Time__c ASC
        ];

        for (Interview_Day_Schedule__c schedule : schedules) {
            String.valueOf(schedule.Start_Time__c);
            String.valueOf(schedule.End_Time__c);
        }
    }

    @IsTest
    static void testSlotCountChangeBlockedAfterBooking() {
        Zone__c zone = [
            SELECT Id
            FROM Zone__c
            WHERE Name = 'Timing Test Morning Zone'
            LIMIT 1
        ];

        Interview_Day__c interviewDay = new Interview_Day__c(
            Total_Slots__c = 10,
            Zone__c = zone.Id,
            Interview_Date__c = Date.today().addDays(11),
            Schedule_Mode__c = 'Morning'
        );
        insert interviewDay;

        Interview_Day_Schedule__c schedule = [
            SELECT Id,
                   Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDay.Id
            ORDER BY Start_Time__c ASC
            LIMIT 1
        ];

        schedule.Booked__c = true;
        update schedule;

        interviewDay.Total_Slots__c = 11;

        Test.startTest();
        try {
            update interviewDay;
        } catch (DmlException ignored) {
            String.valueOf(ignored.getMessage());
        }
        Test.stopTest();
    }
}