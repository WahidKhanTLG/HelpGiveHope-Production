public without sharing class YearRoundAssistanceFormController {

    @AuraEnabled(cacheable=true)
    public static Map<string, List<PickListOption>> getPicklistValues() {
        Map<string, List<PickListOption>> picklistFieldValues = new Map<string, List<PickListOption>>();
        try {
            List<Schema.DescribeFieldResult> ListOfFieldSchema = new List<Schema.DescribeFieldResult> {
                Contact.TLG_Employed_or_unemployed__c.getDescribe(),

                Contact.GenderIdentity.getDescribe(),
                Contact.TLG_Are_you_their_legal_guardian__c.getDescribe(),
                Contact.TLG_Do_you_have_a_shutoff_notice__c.getDescribe(),
                Contact.TLG_Have_you_reached_out_to_OACAC__c.getDescribe(),
                Contact.TLG_Has_OACAC_made_a_determination__c.getDescribe(),

                npe4__Relationship__c.npe4__Type__c.getDescribe(),
                npe4__Relationship__c.Adult_Type__c.getDescribe()
            };

            for(Schema.DescribeFieldResult fieldSchema : ListOfFieldSchema) {
                List<PickListOption> pickListOptions = new List<PickListOption>();

                List<Schema.PicklistEntry> entries = fieldSchema.getPicklistValues();
                for (Schema.PicklistEntry entry : entries) {
                    pickListOptions.add(new PickListOption(entry.getLabel(), entry.getValue()));
                }
                
                string apiName = fieldSchema.getName();
                picklistFieldValues.put(apiName, pickListOptions);
            }
        } catch (Exception ex) {
            system.debug(ex.getMessage());
        }

        return picklistFieldValues;
    }

    @AuraEnabled(cacheable=true)
    public static List<TLG_Poverty_Guideline__c> getPovertyGuidelines() {
        return [
            Select 
                Id, Name, TLG_External_Id__c, TLG_Year__c, 
                TLG_Household_Size__c,  TLG_Income__c 
            From 
                TLG_Poverty_Guideline__c 
            Order By 
                TLG_Year__c DESC, 
                TLG_Household_Size__c DESC 
            LIMIT 100
        ];
    }

    @AuraEnabled(cacheable=false)
    public static String save(String payloadJson) {
        Savepoint sp = Database.setSavepoint();
        try {
            Payload payload = (Payload) JSON.deserialize(payloadJson, Payload.class);

            // ----------------------------------------------------
            // 1) Account resolve by applicant email
            // ----------------------------------------------------
            Account account = payload.account;
            prepareAccount(account);

            List<Account> existingAccounts = [
                SELECT Id, npe01__One2OneContact__c
                FROM Account
                WHERE Primary_Email_Formula__c = :payload.applicant.Email
                Order By CreatedDate DESC
                LIMIT 1
            ];

            Id existingAccountId = existingAccounts.isEmpty() ? null : existingAccounts[0].Id;
            Id existingOneToOneContactId = existingAccounts.isEmpty() ? null : existingAccounts[0].npe01__One2OneContact__c;

            if (existingAccountId != null) {
                account.Id = existingAccountId;
                update account;
            } else {
                insert account;
            }

            // ----------------------------------------------------
            // 2) Applicant resolve by Email + Birthdate
            // ----------------------------------------------------
            Contact applicant = payload.applicant;
            applicant.AccountId = account.Id;

            List<Contact> existingApplicants = [
                SELECT Id
                FROM Contact
                WHERE Email = :applicant.Email
                AND Birthdate = :applicant.Birthdate
                AND AccountId = :account.Id
                LIMIT 1
            ];

            if (!existingApplicants.isEmpty()) {
                applicant.Id = existingApplicants[0].Id;
                update applicant;
            } else {
                insert applicant;
            }

            // ----------------------------------------------------
            // 3) Account one-to-one contact update
            // ----------------------------------------------------
            if (existingOneToOneContactId != applicant.Id) {
                update new Account(
                    Id = account.Id,
                    npe01__One2OneContact__c = applicant.Id
                );
            }

            // ----------------------------------------------------
            // 4) Preload existing household contacts
            //    Match rule for child/adult:
            //    AccountId + FirstName + LastName + Birthdate
            // ----------------------------------------------------
            List<Contact> existingHouseholdContacts = [
                SELECT Id, AccountId, FirstName, LastName, Birthdate
                FROM Contact
                WHERE AccountId = :account.Id
            ];

            Map<String, Contact> existingContactMap = new Map<String, Contact>();
            for (Contact con : existingHouseholdContacts) {
                String key = con.AccountId + '|' + con.FirstName + '|' + con.LastName + '|' + String.valueOf(con.Birthdate);
                existingContactMap.put(key, con);
            }

            // ----------------------------------------------------
            // 5) Resolve children
            // ----------------------------------------------------
            List<Contact> childrenToInsert = new List<Contact>();
            List<Contact> childrenToUpdate = new List<Contact>();
            List<Contact> resolvedChildren = new List<Contact>();

            for (ChildPayload childPayload : payload.children) {
                Contact child = childPayload.child;
                child.AccountId = account.Id;

                String childKey = child.AccountId + '|' + child.FirstName + '|' + child.LastName + '|' + String.valueOf(child.Birthdate);

                if (existingContactMap.containsKey(childKey)) {
                    child.Id = existingContactMap.get(childKey).Id;
                    childrenToUpdate.add(child);
                } else {
                    childrenToInsert.add(child);
                }

                resolvedChildren.add(child);
            }

            if (!childrenToInsert.isEmpty()) {
                insert childrenToInsert;

                for (Contact child : childrenToInsert) {
                    String childKey = child.AccountId + '|' + child.FirstName + '|' + child.LastName + '|' + String.valueOf(child.Birthdate);
                    existingContactMap.put(childKey, child);
                }
            }

            if (!childrenToUpdate.isEmpty()) {
                update childrenToUpdate;
            }

            // ----------------------------------------------------
            // 6) Resolve adults
            // ----------------------------------------------------
            List<Contact> adultsToInsert = new List<Contact>();
            List<Contact> adultsToUpdate = new List<Contact>();
            List<Contact> resolvedAdults = new List<Contact>();

            for (AdultPayload adultPayload : payload.adults) {
                Contact adult = adultPayload.adult;
                adult.AccountId = account.Id;

                String adultKey = adult.AccountId + '|' + adult.FirstName + '|' + adult.LastName + '|' + String.valueOf(adult.Birthdate);

                if (existingContactMap.containsKey(adultKey)) {
                    adult.Id = existingContactMap.get(adultKey).Id;
                    adultsToUpdate.add(adult);
                } else {
                    adultsToInsert.add(adult);
                }

                resolvedAdults.add(adult);
            }

            if (!adultsToInsert.isEmpty()) {
                insert adultsToInsert;

                for (Contact adult : adultsToInsert) {
                    String adultKey = adult.AccountId + '|' + adult.FirstName + '|' + adult.LastName + '|' + String.valueOf(adult.Birthdate);
                    existingContactMap.put(adultKey, adult);
                }
            }

            if (!adultsToUpdate.isEmpty()) {
                update adultsToUpdate;
            }

            // ----------------------------------------------------
            // 7) Case always new
            // ----------------------------------------------------
            Case assistanceCase = payload.assistanceCase;
            if (assistanceCase != null) {
                assistanceCase.AccountId = account.Id;
                assistanceCase.ContactId = applicant.Id;
                normalizeCaseRecordType(assistanceCase);
                insert assistanceCase;
            }

            // ----------------------------------------------------
            // 8) Landlord
            // ----------------------------------------------------

            TLG_LandLord__c landlord = payload.landlord;
            if (landlord != null) {
                landlord.TLG_Contact__c = applicant.Id;

                if (assistanceCase != null) {
                    landlord.Case__c = assistanceCase.Id;
                }

                insert landlord;
            }



            // ----------------------------------------------------
            // 9) Preload existing relationships
            // ----------------------------------------------------
            Set<Id> relatedContactIds = new Set<Id>();

            for (Contact child : resolvedChildren) {
                if (child.Id != null) {
                    relatedContactIds.add(child.Id);
                }
            }

            for (Contact adult : resolvedAdults) {
                if (adult.Id != null) {
                    relatedContactIds.add(adult.Id);
                }
            }

            Map<Id, npe4__Relationship__c> existingRelationshipMap = new Map<Id, npe4__Relationship__c>();
            if (!relatedContactIds.isEmpty()) {
                for (npe4__Relationship__c rel : [
                    SELECT Id, npe4__RelatedContact__c
                    FROM npe4__Relationship__c
                    WHERE npe4__Contact__c = :applicant.Id
                    AND npe4__RelatedContact__c IN :relatedContactIds
                ]) {
                    existingRelationshipMap.put(rel.npe4__RelatedContact__c, rel);
                }
            }

            // ----------------------------------------------------
            // 10) Insert only missing relationships
            // ----------------------------------------------------
            List<npe4__Relationship__c> relationshipsToInsert = new List<npe4__Relationship__c>();

            for (Integer i = 0; i < payload.children.size(); i++) {
                ChildPayload childPayload = payload.children[i];
                Contact childContact = resolvedChildren[i];

                if (!existingRelationshipMap.containsKey(childContact.Id)) {
                    relationshipsToInsert.add(new npe4__Relationship__c(
                        npe4__Contact__c = applicant.Id,
                        npe4__RelatedContact__c = childContact.Id,
                        npe4__Type__c = childPayload.relationshipWithApplicant
                    ));
                }
            }

            for (Integer i = 0; i < payload.adults.size(); i++) {
                AdultPayload adultPayload = payload.adults[i];
                Contact adultContact = resolvedAdults[i];

                if (!existingRelationshipMap.containsKey(adultContact.Id)) {
                    relationshipsToInsert.add(new npe4__Relationship__c(
                        npe4__Contact__c = applicant.Id,
                        npe4__RelatedContact__c = adultContact.Id,
                        Adult_Type__c = adultPayload.relationshipWithApplicant,
                        Adult_Type_Custom__c = adultPayload.customRelationshipWithApplicant
                    ));
                }
            }

            if (!relationshipsToInsert.isEmpty()) {
                insert relationshipsToInsert;
            }

            Database.releaseSavepoint(sp);
            return 'OK';

        } catch (Exception ex) {
            Database.rollback(sp);
            return ''
                + '\nMessage: ' + ex.getMessage()
                + '\nLineNumber: ' + ex.getLineNumber()
                + '\nStackTrace: ' + ex.getStackTraceString()
                + '\nExceptionType: ' + ex.getTypeName();
        }
    }

    private static void normalizeCaseRecordType(Case assistanceCase) {
        if (assistanceCase == null || assistanceCase.RecordTypeId != null) {
            return;
        }

        SObject recordTypeRelationship = assistanceCase.getSObject('RecordType');
        String developerName = recordTypeRelationship == null
            ? null
            : String.valueOf(recordTypeRelationship.get('DeveloperName')).trim();

        if (String.isBlank(developerName)) {
            return;
        }

        RecordType caseRecordType = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND DeveloperName = :developerName
            LIMIT 1
        ];

        assistanceCase.RecordTypeId = caseRecordType.Id;
        assistanceCase.putSObject('RecordType', null);
    }


    public static void prepareAccount(Account acc) {
              Map<String, String> stateMap = new Map<String, String>();
              for (State_Province_Codes__mdt rec : [
                   SELECT State__c, Codes__c FROM State_Province_Codes__mdt
                    ]) {
                   stateMap.put(rec.State__c.toLowerCase(), rec.Codes__c);
                                          }

                   if (String.isNotBlank(acc.BillingState)) {
                      String inputState = acc.BillingState.toLowerCase();
                            if (stateMap.containsKey(inputState)) {
                              acc.BillingState = stateMap.get(inputState);
                }
          }
  }

    public class ChildPayload
    {
        public Contact child { get; set; }
        public string relationshipWithApplicant { get; set; }
    }

    public class AdultPayload
    {
        public Contact adult { get; set; }
        public string relationshipWithApplicant { get; set; }
        public string customRelationshipWithApplicant { get; set; }
    }

    public class Payload
    {
        public Account account { get; set; }
        public Case assistanceCase { get; set; }
        public Contact applicant { get; set; }
        public List<ChildPayload> children { get; set; }
        public List<AdultPayload> adults { get; set; }
        public TLG_LandLord__c landlord { get; set; }
        public TLG_LandLord__c previousLandlord { get; set; }
    }

    public class PickListOption
    {
        @AuraEnabled public string label { get; set; }
        @AuraEnabled public string value { get; set; }

        public PickListOption(string label, string value) {
            this.label = label;
            this.value = value;
        }
    }
}