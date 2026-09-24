public without sharing class YearRoundAssistanceFormController {
    private static final Integer MAX_MEMBERS = 50;
    private class ApplicationException extends Exception {}

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
        try {
            if (String.isBlank(payloadJson) || payloadJson.length() > 200000) {
                return 'The application request is empty or too large.';
            }
            Payload request = (Payload) JSON.deserialize(payloadJson, Payload.class);
            if (request == null || request.account == null || request.applicant == null) {
                return 'Applicant and household information are required.';
            }
            if (request.reuseAccountId != null) {
                return HghHouseholdReuseController.saveReuse(request);
            }
            // Existing IDs must use the permission-checked reuse path, never the legacy new path.
            if ((request.memberStatusUpdates != null && !request.memberStatusUpdates.isEmpty()) ||
                request.reuseRecordVersions != null || request.account.Id != null || request.applicant.Id != null ||
                (request.assistanceCase != null && request.assistanceCase.Id != null)) {
                return 'Please search for the existing household again before submitting.';
            }
            if (request.children != null) for (ChildPayload row : request.children) {
                if (row == null || row.child == null || row.child.Id != null) {
                    return 'Please review the child information and try again.';
                }
            }
            if (request.adults != null) for (AdultPayload row : request.adults) {
                if (row == null || row.adult == null || row.adult.Id != null) {
                    return 'Please review the adult information and try again.';
                }
            }
            if (request.children == null) request.children = new List<ChildPayload>();
            if (request.adults == null) request.adults = new List<AdultPayload>();
            return saveNewApplication(JSON.serialize(request));
        } catch (Exception ignored) {
            return 'The application could not be processed. Please check the information and try again.';
        }
    }

    private static String saveNewApplication(String payloadJson) {
        Savepoint sp = Database.setSavepoint();
        try {
            Payload payload = (Payload) JSON.deserialize(payloadJson, Payload.class);
            if (payload == null || payload.account == null || payload.applicant == null) {
                throw new ApplicationException('Applicant and household information are required.');
            }
            if (payload.children == null) payload.children = new List<ChildPayload>();
            if (payload.adults == null) payload.adults = new List<AdultPayload>();
            if (1 + payload.children.size() + payload.adults.size() > MAX_MEMBERS) {
                throw new ApplicationException('This household needs assisted processing. Please contact Help Give Hope.');
            }

            // SSN is the identity key for public form duplicate prevention.
            // Name and date of birth are no longer used to create/reuse Contacts.
            Set<String> submittedSsnKeys = new Set<String>();
            Set<Decimal> submittedSsnValues = new Set<Decimal>();
            String applicantSsnKey = collectRequiredSsn(payload.applicant, 'Applicant', submittedSsnKeys, submittedSsnValues);
            for (ChildPayload childPayload : payload.children) {
                if (childPayload == null || childPayload.child == null) {
                    throw new ApplicationException('Review the child information and try again.');
                }
                collectRequiredSsn(childPayload.child, 'Child', submittedSsnKeys, submittedSsnValues);
            }
            for (AdultPayload adultPayload : payload.adults) {
                if (adultPayload == null || adultPayload.adult == null) {
                    throw new ApplicationException('Review the adult information and try again.');
                }
                collectRequiredSsn(adultPayload.adult, 'Adult', submittedSsnKeys, submittedSsnValues);
            }

            Map<String, List<Contact>> contactsBySsn = loadContactsBySsn(submittedSsnValues);
            Contact existingApplicant = singleContactForSsn(contactsBySsn, applicantSsnKey, 'Applicant');

            Account account = payload.account;
            prepareAccount(account);

            Id existingOneToOneContactId;
            if (existingApplicant != null) {
                if (existingApplicant.AccountId == null) {
                    throw new ApplicationException('The matching applicant is not linked to a household. Staff review is required.');
                }
                account.Id = existingApplicant.AccountId;
                existingOneToOneContactId = loadOneToOneContactId(account.Id);
                updateExistingAccountFromPayload(account);
            } else {
                Database.insert(account, AccessLevel.SYSTEM_MODE);
            }

            Contact applicant = payload.applicant;
            applicant.AccountId = account.Id;
            applicant.TLG_Social_Security_Number__c = Decimal.valueOf(applicantSsnKey);
            markActive(applicant);

            if (existingApplicant != null) {
                applicant.Id = existingApplicant.Id;
                Database.update(applicant, AccessLevel.SYSTEM_MODE);
            } else {
                Database.insert(applicant, AccessLevel.SYSTEM_MODE);
            }

            if (existingOneToOneContactId != applicant.Id) {
                Database.update(new Account(
                    Id = account.Id,
                    npe01__One2OneContact__c = applicant.Id
                ), AccessLevel.SYSTEM_MODE);
            }

            List<Contact> childrenToInsert = new List<Contact>();
            List<Contact> childrenToUpdate = new List<Contact>();
            List<Contact> resolvedChildren = new List<Contact>();

            for (ChildPayload childPayload : payload.children) {
                Contact child = childPayload.child;
                String childSsnKey = ssnDigits(child.TLG_Social_Security_Number__c);
                Contact existingChild = singleContactForSsn(contactsBySsn, childSsnKey, 'Child');

                child.AccountId = account.Id;
                child.TLG_Social_Security_Number__c = Decimal.valueOf(childSsnKey);
                markActive(child);

                if (existingChild != null) {
                    if (existingChild.AccountId != account.Id) {
                        throw new ApplicationException('A child SSN already exists under another household. Please contact Help Give Hope before submitting.');
                    }
                    child.Id = existingChild.Id;
                    childrenToUpdate.add(child);
                } else {
                    childrenToInsert.add(child);
                }
                resolvedChildren.add(child);
            }

            List<Contact> adultsToInsert = new List<Contact>();
            List<Contact> adultsToUpdate = new List<Contact>();
            List<Contact> resolvedAdults = new List<Contact>();

            for (AdultPayload adultPayload : payload.adults) {
                Contact adult = adultPayload.adult;
                String adultSsnKey = ssnDigits(adult.TLG_Social_Security_Number__c);
                Contact existingAdult = singleContactForSsn(contactsBySsn, adultSsnKey, 'Adult');

                adult.AccountId = account.Id;
                adult.TLG_Social_Security_Number__c = Decimal.valueOf(adultSsnKey);
                markActive(adult);

                if (existingAdult != null) {
                    if (existingAdult.AccountId != account.Id) {
                        throw new ApplicationException('An adult SSN already exists under another household. Please contact Help Give Hope before submitting.');
                    }
                    adult.Id = existingAdult.Id;
                    adultsToUpdate.add(adult);
                } else {
                    adultsToInsert.add(adult);
                }
                resolvedAdults.add(adult);
            }

            if (!childrenToInsert.isEmpty()) Database.insert(childrenToInsert, AccessLevel.SYSTEM_MODE);
            if (!childrenToUpdate.isEmpty()) Database.update(childrenToUpdate, AccessLevel.SYSTEM_MODE);
            if (!adultsToInsert.isEmpty()) Database.insert(adultsToInsert, AccessLevel.SYSTEM_MODE);
            if (!adultsToUpdate.isEmpty()) Database.update(adultsToUpdate, AccessLevel.SYSTEM_MODE);

            Case assistanceCase = payload.assistanceCase;
            if (assistanceCase != null) {
                assistanceCase.AccountId = account.Id;
                assistanceCase.ContactId = applicant.Id;
                normalizeCaseRecordType(assistanceCase);
                Database.insert(assistanceCase, AccessLevel.SYSTEM_MODE);
            }

            TLG_LandLord__c landlord = payload.landlord;
            if (landlord != null) {
                landlord.TLG_Contact__c = applicant.Id;
                if (assistanceCase != null) landlord.Case__c = assistanceCase.Id;
                Database.insert(landlord, AccessLevel.SYSTEM_MODE);
            }

            Set<Id> relatedContactIds = new Set<Id>();
            for (Contact child : resolvedChildren) if (child.Id != null) relatedContactIds.add(child.Id);
            for (Contact adult : resolvedAdults) if (adult.Id != null) relatedContactIds.add(adult.Id);

            Map<Id, npe4__Relationship__c> existingRelationshipMap = new Map<Id, npe4__Relationship__c>();
            if (!relatedContactIds.isEmpty()) {
                for (npe4__Relationship__c rel : [
                    SELECT Id, npe4__RelatedContact__c
                    FROM npe4__Relationship__c
                    WHERE npe4__Contact__c = :applicant.Id
                    AND npe4__RelatedContact__c IN :relatedContactIds
                    WITH SYSTEM_MODE
                ]) {
                    existingRelationshipMap.put(rel.npe4__RelatedContact__c, rel);
                }
            }

            List<npe4__Relationship__c> relationshipsToInsert = new List<npe4__Relationship__c>();
            List<npe4__Relationship__c> relationshipsToUpdate = new List<npe4__Relationship__c>();

            for (Integer i = 0; i < payload.children.size(); i++) {
                ChildPayload childPayload = payload.children[i];
                Contact childContact = resolvedChildren[i];
                npe4__Relationship__c rel = existingRelationshipMap.get(childContact.Id);
                if (rel == null) {
                    rel = new npe4__Relationship__c(
                        npe4__Contact__c = applicant.Id,
                        npe4__RelatedContact__c = childContact.Id
                    );
                    relationshipsToInsert.add(rel);
                } else {
                    relationshipsToUpdate.add(rel);
                }
                rel.npe4__Type__c = childPayload.relationshipWithApplicant;
            }

            for (Integer i = 0; i < payload.adults.size(); i++) {
                AdultPayload adultPayload = payload.adults[i];
                Contact adultContact = resolvedAdults[i];
                npe4__Relationship__c rel = existingRelationshipMap.get(adultContact.Id);
                if (rel == null) {
                    rel = new npe4__Relationship__c(
                        npe4__Contact__c = applicant.Id,
                        npe4__RelatedContact__c = adultContact.Id
                    );
                    relationshipsToInsert.add(rel);
                } else {
                    relationshipsToUpdate.add(rel);
                }
                rel.Adult_Type__c = adultPayload.relationshipWithApplicant;
                rel.Adult_Type_Custom__c = adultPayload.customRelationshipWithApplicant;
            }

            if (!relationshipsToInsert.isEmpty()) Database.insert(relationshipsToInsert, AccessLevel.SYSTEM_MODE);
            if (!relationshipsToUpdate.isEmpty()) Database.update(relationshipsToUpdate, AccessLevel.SYSTEM_MODE);

            Database.releaseSavepoint(sp);
            return 'OK';
        } catch (ApplicationException ex) {
            Database.rollback(sp);
            return ex.getMessage();
        } catch (Exception ex) {
            Database.rollback(sp);
            return 'The application could not be saved. Please review the required information or contact Help Give Hope.';
        }
    }

    private static String collectRequiredSsn(Contact member, String label, Set<String> seen, Set<Decimal> values) {
        if (member == null || member.TLG_Social_Security_Number__c == null) {
            throw new ApplicationException('Enter a Social Security Number for every applicant, adult, and child.');
        }
        String canonical = ssnDigits(member.TLG_Social_Security_Number__c);
        if (seen.contains(canonical)) {
            throw new ApplicationException('Two listed household members have the same Social Security Number. Each household member must have a unique SSN.');
        }
        seen.add(canonical);
        values.add(Decimal.valueOf(canonical));
        return canonical;
    }

    private static String ssnDigits(Decimal value) {
        if (value == null) return null;
        Decimal whole = value.setScale(0);
        if (value < 0 || value > 999999999 || value != whole) {
            throw new ApplicationException('A Social Security Number needs review. Please check the information or contact Help Give Hope.');
        }
        return String.valueOf(whole).leftPad(9, '0');
    }

    private static Map<String, List<Contact>> loadContactsBySsn(Set<Decimal> values) {
        Map<String, List<Contact>> result = new Map<String, List<Contact>>();
        if (values == null || values.isEmpty()) return result;

        for (Contact existing : [
            SELECT Id, AccountId, TLG_Social_Security_Number__c
            FROM Contact
            WHERE TLG_Social_Security_Number__c IN :values
            WITH SYSTEM_MODE
        ]) {
            String key = ssnDigits(existing.TLG_Social_Security_Number__c);
            if (!result.containsKey(key)) result.put(key, new List<Contact>());
            result.get(key).add(existing);
        }
        return result;
    }

    private static Contact singleContactForSsn(Map<String, List<Contact>> contactsBySsn, String canonicalSsn, String label) {
        List<Contact> matches = contactsBySsn == null ? null : contactsBySsn.get(canonicalSsn);
        if (matches == null || matches.isEmpty()) return null;
        if (matches.size() > 1) {
            throw new ApplicationException(label + ' SSN matches multiple Contacts. Staff review is required.');
        }
        return matches[0];
    }

    private static Id loadOneToOneContactId(Id accountId) {
        List<Account> accounts = [
            SELECT Id, npe01__One2OneContact__c
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new ApplicationException('The matching household could not be loaded. Staff review is required.');
        }
        return accounts[0].npe01__One2OneContact__c;
    }

    private static void updateExistingAccountFromPayload(Account submitted) {
        Account updateRow = new Account(
            Id = submitted.Id,
            BillingStreet = submitted.BillingStreet,
            BillingCity = submitted.BillingCity,
            BillingState = submitted.BillingState,
            BillingPostalCode = submitted.BillingPostalCode,
            BillingCountry = submitted.BillingCountry,
            ShippingStreet = submitted.ShippingStreet,
            ShippingCity = submitted.ShippingCity,
            ShippingState = submitted.ShippingState,
            ShippingPostalCode = submitted.ShippingPostalCode,
            ShippingCountry = submitted.ShippingCountry,
            How_long_have_you_lived_at_this_address__c = submitted.How_long_have_you_lived_at_this_address__c,
            How_long_did_you_live_there__c = submitted.How_long_did_you_live_there__c,
            Interested_in_Santa_Gifts__c = submitted.Interested_in_Santa_Gifts__c
        );
        prepareAccount(updateRow);
        Database.update(updateRow, AccessLevel.SYSTEM_MODE);
    }

    private static void markActive(Contact contactRecord) {
        contactRecord.TLG_Household_Member_Status__c = 'Active';
        contactRecord.TLG_Household_Member_Status_Reason__c = null;
    }

    public static void normalizeCaseRecordType(Case assistanceCase) {
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

    public class MemberStatusPayload {
        public Id contactId { get; set; }
        public String status { get; set; }
        public String reason { get; set; }
    }

    public class Payload {
        public Id reuseAccountId { get; set; }
        public Map<String, String> reuseRecordVersions { get; set; }
        public Account account { get; set; }
        public Case assistanceCase { get; set; }
        public Contact applicant { get; set; }
        public List<ChildPayload> children { get; set; }
        public List<AdultPayload> adults { get; set; }
        public List<MemberStatusPayload> memberStatusUpdates { get; set; }
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