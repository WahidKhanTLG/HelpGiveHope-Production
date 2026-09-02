/**
 * Helper class for schedule generation functionality
 * Handles caching and data preparation for LWC components
 */
public with sharing class ScheduleGenHelper {
    
    /**
     * DTO for UI options like dropdown selections
     */
    public class OptionDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }
    
    /**
     * Summary data for a schedule year
     */
    public class YearSummaryDTO {
        @AuraEnabled public Id scheduleYearId;
        @AuraEnabled public Integer plannedCount;
        @AuraEnabled public Integer publishedCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<ZoneSummaryDTO> byZone;
    }
    
    /**
     * Zone-specific summary data
     */
    public class ZoneSummaryDTO {
        @AuraEnabled public Id zoneId;
        @AuraEnabled public String zoneName;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer plannedRecords;
        @AuraEnabled public Integer publishedRecords;
    }

    /**
     * Get active zone options for UI dropdowns/selection
     * @return List of zone options
     */
    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> getZoneOptions() {
        List<OptionDTO> opts = new List<OptionDTO>();
        for (Zone__c z : [SELECT Id, Name FROM Zone__c WHERE Active__c = true ORDER BY Name]) {
            OptionDTO o = new OptionDTO();
            o.label = z.Name;
            o.value = (String)z.Id;
            opts.add(o);
        }
        return opts;
    }

    /**
     * Ensure a schedule year record exists, creating it if necessary
     * @param year The year to ensure
     * @return Id of the schedule year record
     */
    @AuraEnabled
    public static Id ensureScheduleYear(Integer year) {
        if (year == null) throw new AuraHandledException('Year is required');
        List<Schedule_Year__c> y = [SELECT Id FROM Schedule_Year__c WHERE Year__c = :year LIMIT 1];
        if (!y.isEmpty()) return y[0].Id;
        
        Schedule_Year__c s = new Schedule_Year__c(
            Name = String.valueOf(year), 
            Year__c = year, 
            Status__c = 'Planned'
        );
        insert s;
        return s.Id;
    }

    /**
     * Get available year options from existing schedule years
     * @return List of year options for UI
     */
    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> getYearOptions() {
        List<OptionDTO> opts = new List<OptionDTO>();
        for (Schedule_Year__c sy : [SELECT Year__c FROM Schedule_Year__c ORDER BY Year__c DESC LIMIT 100]) {
            OptionDTO o = new OptionDTO();
            o.label = String.valueOf(sy.Year__c);
            o.value = String.valueOf(sy.Year__c);
            opts.add(o);
        }
        return opts;
    }

    /**
     * Get summary statistics for a schedule year, including zone-specific data
     * @param year The year to summarize
     * @return YearSummaryDTO with count information
     */
    @AuraEnabled
    public static YearSummaryDTO getScheduleYearSummary(Integer year) {
        if (year == null) throw new AuraHandledException('Year is required');
        
        YearSummaryDTO dto = new YearSummaryDTO();
        dto.plannedCount = 0;
        dto.publishedCount = 0;
        dto.totalCount = 0;
        dto.byZone = new List<ZoneSummaryDTO>();
        
        List<Schedule_Year__c> ys = [SELECT Id FROM Schedule_Year__c WHERE Year__c = :year LIMIT 1];
        if (ys.isEmpty()) {
            return dto;
        }
        
        Id sid = ys[0].Id;
        dto.scheduleYearId = sid;
        
        // Get overall counts by status
        for (AggregateResult ar : [
            SELECT Status__c s, COUNT(Id) c
            FROM Schedule_Date__c
            WHERE Schedule_Year__c = :sid
            GROUP BY Status__c
        ]) {
            String s = (String)ar.get('s');
            Integer c = (Integer)ar.get('c');
            dto.totalCount += c;
            if (s == 'Planned') dto.plannedCount += c;
            else if (s == 'Published') dto.publishedCount += c;
        }
        
        // Get zone-specific counts
        Map<Id, ZoneSummaryDTO> zoneMap = new Map<Id, ZoneSummaryDTO>();
        for (AggregateResult ar : [
            SELECT Zone__c zid, Zone__r.Name zname, Status__c s, COUNT(Id) c
            FROM Schedule_Date__c
            WHERE Schedule_Year__c = :sid
            GROUP BY Zone__c, Zone__r.Name, Status__c
        ]) {
            Id zid = (Id)ar.get('zid');
            String zname = (String)ar.get('zname');
            String status = (String)ar.get('s');
            Integer count = (Integer)ar.get('c');
            
            if (!zoneMap.containsKey(zid)) {
                ZoneSummaryDTO zs = new ZoneSummaryDTO();
                zs.zoneId = zid;
                zs.zoneName = zname;
                zs.totalRecords = 0;
                zs.plannedRecords = 0;
                zs.publishedRecords = 0;
                zoneMap.put(zid, zs);
            }
            
            ZoneSummaryDTO zs = zoneMap.get(zid);
            zs.totalRecords += count;
            if (status == 'Planned') zs.plannedRecords += count;
            else if (status == 'Published') zs.publishedRecords += count;
        }
        
        dto.byZone = zoneMap.values();
        return dto;
    }
}