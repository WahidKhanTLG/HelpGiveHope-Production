/**
 * Utility functions for date handling and UI display
 * Enhanced with additional functions for the integrated component
 */

/**
 * Formats a month number (1-12) as a month name
 * @param {Number} m Month number (1-12)
 * @returns {String} Month name
 */
const monthText = (m) => {
    return new Date(2000, m-1, 1).toLocaleString('en-US', { month: 'long' });
};

/**
 * Formats a day of week number (1-7) as a three-letter abbreviation
 * @param {Number} d Day of week number (1=Sun, 7=Sat)
 * @returns {String} Three-letter day abbreviation
 */
const dowText = (d) => {
    return ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][d-1];
};

/**
 * Calculates the appropriate ordinal suffix for a number
 * @param {Number} n Input number
 * @returns {String} Ordinal suffix ('st', 'nd', 'rd', or 'th')
 */
const ordinalSuffix = (n) => {
    // Robust suffix calculation for positive integers
    const v = Math.abs(n);
    const j = v % 10, k = v % 100;
    if (j === 1 && k !== 11) return 'st';
    if (j === 2 && k !== 12) return 'nd';
    if (j === 3 && k !== 13) return 'rd';
    return 'th';
};

/**
 * Formats a number with its ordinal suffix, handling special case for "Last"
 * @param {Number} n Number to format
 * @returns {String} Formatted ordinal label
 */
const ordinalLabel = (n) => {
    // Treat -1 and 5 (when used for rules) as "Last"
    if (n === -1 || n === 5) return 'Last';
    if (typeof n === 'number' && Number.isInteger(n)) return `${n}${ordinalSuffix(n)}`;
    return '';
};

/**
 * Returns CSS class based on action type
 * @param {String} action Action type ('CREATE', 'UPDATE', 'SKIP')
 * @returns {String} CSS class string
 */
const getActionClass = (action) => {
    switch(action) {
        case 'CREATE': return 'slds-text-color_success slds-text-title_bold';
        case 'UPDATE': return 'slds-text-color_warning slds-text-title_bold';
        case 'SKIP': return 'slds-text-color_weak';
        default: return '';
    }
};

/**
 * Builds a rule description label
 * @param {Number} ordinal Ordinal value (1-5)
 * @param {Number} dow Day of week (1-7)
 * @param {Number} month Month (1-12)
 * @returns {String} Formatted rule description
 */
const buildRuleText = (ordinal, dow, month) => {
    return `${ordinalLabel(ordinal)} ${dowText(dow)} of ${monthText(month)}`;
};

/**
 * Formats a date object into YYYY-MM-DD string format
 * @param {Date} date - The date to format
 * @return {String} Formatted date string
 */
const formatDateToString = (date) => {
    if (!date) return '';
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const year = date.getFullYear();
    return `${year}-${month}-${day}`;
};

/**
 * Formats a date string into a more readable format for display
 * @param {String} dateString - Date in format YYYY-MM-DD
 * @return {String} Formatted date for display
 */
const formatDateForDisplay = (dateString) => {
    if (!dateString) return '';
    const date = new Date(dateString);
    return new Intl.DateTimeFormat('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
    }).format(date);
};

/**
 * Groups dates by month for better organization
 * @param {Array} dates - Array of date objects or strings
 * @return {Object} Dates grouped by month
 */
const groupDatesByMonth = (dates) => {
    if (!dates?.length) return {};
    
    const groups = {};
    dates.forEach(dateItem => {
        let date;
        if (typeof dateItem === 'string') {
            date = new Date(dateItem);
        } else if (dateItem instanceof Date) {
            date = dateItem;
        } else if (dateItem.calculatedDate) {
            date = new Date(dateItem.calculatedDate);
        }
        
        if (date) {
            const monthYear = date.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
            if (!groups[monthYear]) {
                groups[monthYear] = [];
            }
            groups[monthYear].push(dateItem);
        }
    });
    
    return groups;
};

/**
 * Gets unique dates from an array
 * @param {Array} dateArray - Array of date strings or objects
 * @return {Array} Array of unique dates
 */
const getUniqueDates = (dateArray) => {
    if (!dateArray?.length) return [];
    
    const uniqueDates = new Set();
    dateArray.forEach(item => {
        let dateStr;
        if (item instanceof Date) {
            dateStr = formatDateToString(item);
        } else if (typeof item === 'string') {
            dateStr = item;
        } else {
            dateStr = item.calculatedDate;
        }
        uniqueDates.add(dateStr);
    });
    
    return Array.from(uniqueDates);
};

export {
    monthText,
    dowText,
    ordinalSuffix,
    ordinalLabel,
    getActionClass,
    buildRuleText,
    formatDateToString,
    formatDateForDisplay,
    groupDatesByMonth,
    getUniqueDates
};