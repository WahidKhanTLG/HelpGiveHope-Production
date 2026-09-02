/**
 * Apex controller for form visibility management
 * Manages visibility of forms based on Form_Catalog__c records
 * Uses 'without sharing' to be accessible to guest users
 */
public without sharing class FormVisibilityController {
    // Custom exception to avoid AuraHandledException restrictions in non-Aura contexts
    public class FormVisibilityException extends Exception {}

    /**
     * Retrieves the status of a form from the Form_Catalog__c object
     * @param formName The name of the form as stored in Form_Catalog__c
     * @return FormStatus Object containing isActive status and optional message
     */
    @AuraEnabled(cacheable=false)
    public static FormStatus getFormStatus(String formName) {
        FormStatus result = new FormStatus();
        try {
            List<Form_Catalog__c> forms = [
                SELECT Id, Name, Status__c, Message__c, Start_Date__c, End_Date__c
                FROM Form_Catalog__c
                WHERE Name = :formName
                LIMIT 1
            ];
            if (!forms.isEmpty()) {
                result.isActive = (forms[0].Status__c == 'Active');
                result.message = String.isNotBlank(forms[0].Message__c)
                    ? forms[0].Message__c
                    : 'This form is currently not available.';
                result.formId = forms[0].Id;
            } else {
                result.isActive = false;
                result.message = 'Form configuration not found.';
            }
        } catch (Exception e) {
            result.isActive = false;
            result.message = 'Error retrieving form status: ' + e.getMessage();
        }
        return result;
    }

    /**
     * Get all form catalogs for administration
     */
    @AuraEnabled(cacheable=true)
    public static List<Form_Catalog__c> getAllFormCatalogs() {
        return [
            SELECT Id, Name, Status__c, Message__c, Start_Date__c, End_Date__c, LastModifiedDate, CreatedDate
            FROM Form_Catalog__c
            ORDER BY Name ASC
        ];
    }

    /**
     * Update a form's status/message/dates
     */
    @AuraEnabled
    public static String updateFormStatus(String formId, Boolean isActive, String message, Date startDate, Date endDate) {
        if (String.isBlank(formId)) {
            throw new FormVisibilityException('Form ID is required');
        }
        try {
            if (!Schema.sObjectType.Form_Catalog__c.isUpdateable()) {
                throw new FormVisibilityException('You do not have permission to update form configurations');
            }
            Form_Catalog__c form = [
                SELECT Id, Message__c, Status__c, Start_Date__c, End_Date__c
                FROM Form_Catalog__c
                WHERE Id = :formId
                LIMIT 1
            ];
            form.Status__c = isActive ? 'Active' : 'Inactive';
            if (message != null) form.Message__c = message;
            form.Start_Date__c = startDate;
            form.End_Date__c = endDate;

            if (form.Start_Date__c != null && form.End_Date__c != null && form.End_Date__c < form.Start_Date__c) {
                throw new FormVisibilityException('End Date cannot be before Start Date.');
            }

            update form;
            return 'success';
        } catch (QueryException e) {
            throw new FormVisibilityException('Form with ID ' + formId + ' not found');
        } catch (DmlException e) {
            throw new FormVisibilityException('Error updating form: ' + e.getMessage());
        } catch (Exception e) {
            throw new FormVisibilityException('Error updating form: ' + e.getMessage());
        }
    }

    /**
     * Create a new form catalog record
     */
    @AuraEnabled
    public static String createFormCatalog(String formName, Boolean isActive, String message, Date startDate, Date endDate) {
        if (String.isBlank(formName)) {
            throw new FormVisibilityException('Form name is required');
        }
        try {
            if (!Schema.sObjectType.Form_Catalog__c.isCreateable()) {
                throw new FormVisibilityException('You do not have permission to create form configurations');
            }
            List<Form_Catalog__c> existingForms = [SELECT Id FROM Form_Catalog__c WHERE Name = :formName LIMIT 1];
            if (!existingForms.isEmpty()) {
                throw new FormVisibilityException('A form with the name "' + formName + '" already exists');
            }

            Form_Catalog__c newForm = new Form_Catalog__c(
                Name = formName,
                Status__c = isActive ? 'Active' : 'Inactive',
                Message__c = message,
                Start_Date__c = startDate,
                End_Date__c = endDate
            );

            if (newForm.Start_Date__c != null && newForm.End_Date__c != null && newForm.End_Date__c < newForm.Start_Date__c) {
                throw new FormVisibilityException('End Date cannot be before Start Date.');
            }

            insert newForm;
            return newForm.Id;
        } catch (DmlException e) {
            throw new FormVisibilityException('Error creating form: ' + e.getMessage());
        } catch (Exception e) {
            if (!(e instanceof FormVisibilityException)) {
                throw new FormVisibilityException('Error creating form: ' + e.getMessage());
            } else {
                throw e;
            }
        }
    }

    /**
     * Helper for scripts/tests
     */
    public static void setFormActiveStatus(String formName, Boolean isActive, String message) {
        List<Form_Catalog__c> forms = [
            SELECT Id, Name, Status__c, Message__c, Start_Date__c, End_Date__c
            FROM Form_Catalog__c
            WHERE Name = :formName
            LIMIT 1
        ];
        if (!forms.isEmpty()) {
            forms[0].Status__c = isActive ? 'Active' : 'Inactive';
            if (message != null) forms[0].Message__c = message;
            try { update forms; } catch (Exception e) { System.debug('Error: ' + e.getMessage()); }
        } else {
            System.debug('Form not found: ' + formName);
        }
    }

    public class FormStatus {
        @AuraEnabled public Boolean isActive = false;
        @AuraEnabled public String  message = '';
        @AuraEnabled public String  formId  = '';
    }
}