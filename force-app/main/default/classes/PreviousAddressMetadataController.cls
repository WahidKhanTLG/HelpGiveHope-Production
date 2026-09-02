public without sharing class PreviousAddressMetadataController {
    public class OptionWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Boolean selected;

        public OptionWrapper(String label, String value) {
            this.label = label;
            this.value = value;
            this.selected = false;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getPreviousStates() {
        List<OptionWrapper> results = new List<OptionWrapper>();

        for (AggregateResult ar : [
            SELECT State_Code__c stateCode, State_Name__c stateName
            FROM State_City_ZipCode__c
            WHERE State_Code__c != null
            GROUP BY State_Code__c, State_Name__c
            ORDER BY State_Name__c
        ]) {
            String stateCode = (String) ar.get('stateCode');
            String stateName = (String) ar.get('stateName');

            if (String.isBlank(stateCode)) {
                continue;
            }

            if (String.isBlank(stateName)) {
                stateName = stateCode;
            }

            results.add(new OptionWrapper(stateName, stateCode));
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getPreviousCities(String stateCode) {
        List<OptionWrapper> results = new List<OptionWrapper>();
        Set<String> addedCities = new Set<String>();

        if (String.isBlank(stateCode)) {
            return results;
        }

        stateCode = stateCode.trim();

        for (State_City_ZipCode__c row : [
            SELECT City_Name__c
            FROM State_City_ZipCode__c
            WHERE State_Code__c = :stateCode
            AND City_Name__c != null
            ORDER BY City_Name__c
        ]) {
            String cityName = row.City_Name__c == null ? '' : row.City_Name__c.trim();
            if (String.isBlank(cityName) || addedCities.contains(cityName)) {
                continue;
            }

            results.add(new OptionWrapper(cityName, cityName));
            addedCities.add(cityName);
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getPreviousZipCodes(String stateCode, String cityName) {
        List<OptionWrapper> results = new List<OptionWrapper>();

        if (String.isBlank(stateCode) || String.isBlank(cityName)) {
            return results;
        }

        stateCode = stateCode.trim();
        cityName = cityName.trim();

        List<State_City_ZipCode__c> rows = [
            SELECT Zip_Codes__c
            FROM State_City_ZipCode__c
            WHERE State_Code__c = :stateCode
            AND City_Name__c = :cityName
            LIMIT 1
        ];

        if (rows.isEmpty() || String.isBlank(rows[0].Zip_Codes__c)) {
            return results;
        }

        Set<String> uniqueZips = new Set<String>();
        for (String zipCode : rows[0].Zip_Codes__c.split(',')) {
            String cleanZip = zipCode == null ? '' : zipCode.trim();
            if (!String.isBlank(cleanZip)) {
                uniqueZips.add(cleanZip);
            }
        }

        List<String> zipList = new List<String>(uniqueZips);
        zipList.sort();

        for (String zipCode : zipList) {
            results.add(new OptionWrapper(zipCode, zipCode));
        }

        return results;
    }
}