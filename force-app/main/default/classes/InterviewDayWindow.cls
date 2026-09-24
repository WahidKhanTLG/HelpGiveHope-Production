/**
 * Interview window arithmetic shared by the Interview Day / Schedule triggers, the booking service
 * and the Google Calendar mirror. Every slot is SLOT_MINUTES long; a day's window starts at
 * Interview_Day__c.Start_Time__c (defaulted from the mode) and ends after Total_Slots__c slots.
 */
public without sharing class InterviewDayWindow {

    public static final Integer SLOT_MINUTES = 15;
    public static final Time MORNING_START = Time.newInstance(8, 0, 0, 0);
    public static final Time AFTERNOON_START = Time.newInstance(12, 30, 0, 0);

    /** Default window start for a schedule mode; null when the mode is not a single-window mode. */
    public static Time defaultStartFor(String mode) {
        if (isMorning(mode)) {
            return MORNING_START;
        }
        if (isAfternoon(mode)) {
            return AFTERNOON_START;
        }
        return null;
    }

    public static Boolean isMorning(String mode) {
        return mode != null && mode.trim().equalsIgnoreCase('Morning');
    }

    public static Boolean isAfternoon(String mode) {
        return mode != null && (mode.trim().equalsIgnoreCase('Afternoon') || mode.trim().equalsIgnoreCase('AfterNoon'));
    }

    /** Start of slot N (1-based) in a window starting at windowStart. */
    public static Time slotStart(Time windowStart, Integer slotNumber) {
        return addMinutes(windowStart, (slotNumber - 1) * SLOT_MINUTES);
    }

    /** End of slot N (1-based). */
    public static Time slotEnd(Time windowStart, Integer slotNumber) {
        return addMinutes(windowStart, slotNumber * SLOT_MINUTES);
    }

    /** End of the whole window for the given number of slots. */
    public static Time windowEnd(Time windowStart, Integer totalSlots) {
        if (windowStart == null || totalSlots == null || totalSlots <= 0) {
            return null;
        }
        return addMinutes(windowStart, totalSlots * SLOT_MINUTES);
    }

    public static Time addMinutes(Time value, Integer minutes) {
        if (value == null) {
            return null;
        }
        Integer total = value.hour() * 60 + value.minute() + minutes;
        total = Math.mod(total, 24 * 60);
        if (total < 0) {
            total += 24 * 60;
        }
        return Time.newInstance(total / 60, Math.mod(total, 60), 0, 0);
    }

    /** "8:00 AM" style label used for the *_Time_Text__c fields, emails and Google descriptions. */
    public static String label(Time value) {
        if (value == null) {
            return null;
        }
        Integer hour = value.hour();
        String suffix = hour >= 12 ? 'PM' : 'AM';
        Integer hour12 = Math.mod(hour, 12);
        if (hour12 == 0) {
            hour12 = 12;
        }
        String minutes = value.minute() < 10 ? '0' + String.valueOf(value.minute()) : String.valueOf(value.minute());
        return hour12 + ':' + minutes + ' ' + suffix;
    }

    public static String rangeLabel(Time startValue, Time endValue) {
        if (startValue == null) {
            return '';
        }
        return label(startValue) + (endValue == null ? '' : ' - ' + label(endValue));
    }
}