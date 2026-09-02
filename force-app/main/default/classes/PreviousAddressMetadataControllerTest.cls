@IsTest
private class PreviousAddressMetadataControllerTest {

    @TestSetup
    static void createTestData() {
        List<State_City_ZipCode__c> recordsToInsert = new List<State_City_ZipCode__c>();

        recordsToInsert.add(new State_City_ZipCode__c(
            State_Code__c = 'AL',
            State_Name__c = 'Alabama',
            City_Name__c = 'Birmingham',
            Zip_Codes__c = '35201,35202,35203'
        ));

        recordsToInsert.add(new State_City_ZipCode__c(
            State_Code__c = 'AL',
            State_Name__c = 'Alabama',
            City_Name__c = 'Montgomery',
            Zip_Codes__c = '36101,36104,36105'
        ));

        recordsToInsert.add(new State_City_ZipCode__c(
            State_Code__c = 'TX',
            State_Name__c = 'Texas',
            City_Name__c = 'Houston',
            Zip_Codes__c = '77001,77002,77003'
        ));

        recordsToInsert.add(new State_City_ZipCode__c(
            State_Code__c = 'TX',
            State_Name__c = 'Texas',
            City_Name__c = 'Dallas',
            Zip_Codes__c = '75001,75002'
        ));

        insert recordsToInsert;
    }

    @IsTest
    static void testGetPreviousStates() {
        Test.startTest();
        List<PreviousAddressMetadataController.OptionWrapper> results =
            PreviousAddressMetadataController.getPreviousStates();
        Test.stopTest();

        for (PreviousAddressMetadataController.OptionWrapper item : results) {
            System.debug('State Label: ' + item.label);
            System.debug('State Value: ' + item.value);
            System.debug('State Selected: ' + item.selected);
        }
    }

    @IsTest
    static void testGetPreviousCities_WithValidState() {
        Test.startTest();
        List<PreviousAddressMetadataController.OptionWrapper> results =
            PreviousAddressMetadataController.getPreviousCities('AL');
        Test.stopTest();

        for (PreviousAddressMetadataController.OptionWrapper item : results) {
            System.debug('City Label: ' + item.label);
            System.debug('City Value: ' + item.value);
            System.debug('City Selected: ' + item.selected);
        }
    }

    @IsTest
    static void testGetPreviousCities_WithBlankState() {
        Test.startTest();
        List<PreviousAddressMetadataController.OptionWrapper> results1 =
            PreviousAddressMetadataController.getPreviousCities(null);

        List<PreviousAddressMetadataController.OptionWrapper> results2 =
            PreviousAddressMetadataController.getPreviousCities('');

        List<PreviousAddressMetadataController.OptionWrapper> results3 =
            PreviousAddressMetadataController.getPreviousCities('   ');
        Test.stopTest();

        System.debug('Blank state results1 size: ' + results1.size());
        System.debug('Blank state results2 size: ' + results2.size());
        System.debug('Blank state results3 size: ' + results3.size());
    }

    @IsTest
    static void testGetPreviousZipCodes_WithValidInputs() {
        Test.startTest();
        List<PreviousAddressMetadataController.OptionWrapper> results =
            PreviousAddressMetadataController.getPreviousZipCodes('AL', 'Birmingham');
        Test.stopTest();

        for (PreviousAddressMetadataController.OptionWrapper item : results) {
            System.debug('Zip Label: ' + item.label);
            System.debug('Zip Value: ' + item.value);
            System.debug('Zip Selected: ' + item.selected);
        }
    }

    @IsTest
    static void testGetPreviousZipCodes_WithBlankInputs() {
        Test.startTest();
        List<PreviousAddressMetadataController.OptionWrapper> results1 =
            PreviousAddressMetadataController.getPreviousZipCodes(null, 'Birmingham');

        List<PreviousAddressMetadataController.OptionWrapper> results2 =
            PreviousAddressMetadataController.getPreviousZipCodes('AL', null);

        List<PreviousAddressMetadataController.OptionWrapper> results3 =
            PreviousAddressMetadataController.getPreviousZipCodes('', '');

        List<PreviousAddressMetadataController.OptionWrapper> results4 =
            PreviousAddressMetadataController.getPreviousZipCodes('   ', '   ');
        Test.stopTest();

        System.debug('Blank zip input results1 size: ' + results1.size());
        System.debug('Blank zip input results2 size: ' + results2.size());
        System.debug('Blank zip input results3 size: ' + results3.size());
        System.debug('Blank zip input results4 size: ' + results4.size());
    }

    @IsTest
    static void testGetPreviousZipCodes_WithNoMatchingCity() {
        Test.startTest();
        List<PreviousAddressMetadataController.OptionWrapper> results =
            PreviousAddressMetadataController.getPreviousZipCodes('AL', 'NoCity');
        Test.stopTest();

        System.debug('No matching city results size: ' + results.size());
    }
}