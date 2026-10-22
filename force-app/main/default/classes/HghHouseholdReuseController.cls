/**
 * Household lookup/reuse using existing Account, Contact, Case and relationship objects.
 * No additional custom object, custom permission, permission set or server session.
 * Public lookup/save runs without sharing and with default (system) CRUD/FLS because the form runs as a Site Guest User.
 * Server-side household, membership, record-version, record-type and SSN protections remain enforced.
 * Record versions are an optimistic-concurrency hint, NOT authorization or proof of lookup.
 */
public without sharing class HghHouseholdReuseController {
    private static final Integer MAX_MEMBERS = 50;
    private static final String SSN_FIELD = 'TLG_Social_Security_Number__c';
    private static final String CONTACT_SELECT = 'SELECT Id, AccountId, FirstName, LastName, Email, '
        + 'Birthdate, GenderIdentity, Phone, TLG_Social_Security_Number__c, TLG_Household_Member_Status__c, '
        + 'TLG_Household_Member_Status_Reason__c, MailingStreet, MailingCity, MailingState, MailingPostalCode, '
        + 'MailingCountry, TLG_Employed_or_unemployed__c, TLG_Employer_Name__c, TLG_Previous_Employer__c, '
        + 'how_long_were_you_employed_there__c, Employment_Unemployment_duration_months__c, '
        + 'TLG_Hours_worked_per_week__c, TLG_Rate_of_Pay__c, Number_of_Jobs_in_Past_36_Months__c, '
        + 'TLG_Total_Time_Employed_Months__c, TLG_Wages_per_month__c, TLG_Relationship_with_Applicant__c, '
        + 'TLG_Are_you_their_legal_guardian__c, School_Attending__c, LastModifiedDate FROM Contact ';
    private static final Set<String> CONTACT_FIELDS = new Set<String>{
        'FirstName', 'LastName', 'Email', 'Birthdate', 'GenderIdentity', 'Phone',
        'MailingStreet', 'MailingCity', 'MailingState', 'MailingPostalCode', 'MailingCountry',
        'TLG_Social_Security_Number__c', 'TLG_Employed_or_unemployed__c',
        'TLG_Employer_Name__c', 'TLG_Previous_Employer__c', 'how_long_were_you_employed_there__c',
        'Employment_Unemployment_duration_months__c', 'TLG_Hours_worked_per_week__c',
        'TLG_Rate_of_Pay__c', 'Number_of_Jobs_in_Past_36_Months__c',
        'TLG_Total_Time_Employed_Months__c', 'TLG_Wages_per_month__c',
        'TLG_Relationship_with_Applicant__c', 'TLG_SSI_Disability__c', 'TLG_TANIF__c',
        'TLG_SS__c', 'TLG_Food_Stamps__c', 'TLG_Unemployment__c', 'TLG_Child_Support__c',
        'TLG_Other__c', 'TLG_Veterans__c', 'TLG_Are_you_their_legal_guardian__c', 'School_Attending__c'
    };
    private static final Set<String> EDITABLE_PREFILL_FIELDS = new Set<String>{
        'FirstName', 'LastName', 'Email', 'Birthdate', 'GenderIdentity',
        'MailingStreet', 'MailingCity', 'MailingState', 'MailingPostalCode'
    };
    private static final Set<String> ACCOUNT_FIELDS = new Set<String>{
        'BillingStreet', 'BillingCity', 'BillingState', 'BillingPostalCode',
        'ShippingStreet', 'ShippingCity', 'ShippingState', 'ShippingPostalCode', 'ShippingCountry',
        'How_long_have_you_lived_at_this_address__c', 'How_long_did_you_live_there__c',
        'Interested_in_Santa_Gifts__c'
    };
    private static final Set<String> CASE_FIELDS = new Set<String>{
        'Adult_Employer_Name__c',
        'Adult_Employment_Duration__c',
        'Adult_Jobs_In_Past_36_Months__c',
        'Adult_Previous_Employer__c',
        'Adult_Total_Time_Employed_Months__c',
        'Applicant_Employer_Name__c',
        'Applicant_Employment_Duration__c',
        'Applicant_Employment_Status__c',
        'Applicant_Previous_Employer__c',
        'Application_Year__c',
        'Assistance_Type__c',
        'Assisted_in_Past_12_Months__c',
        'Employment_Length_Months__c',
        'How_long_did_you_live_there__c',
        'How_long_have_you_lived_at_this_address__c',
        'Interested_in_Santa_Gifts__c',
        'Jobs_In_Past_36_Months__c',
        'Origin',
        'Reason_for_Current_Situation__c',
        'Status',
        'Subject',
        'TLG_Car_Payment__c',
        'TLG_Child_Support__c',
        'TLG_Christmas_Assistance__c',
        'TLG_Credit_Cards__c',
        'TLG_Do_you_have_a_shutoff_notice__c',
        'TLG_Educational_Assistance__c',
        'TLG_Food_Stamps__c',
        'TLG_Groceries__c',
        'TLG_Has_OACAC_made_a_determination__c',
        'TLG_Have_you_reached_out_to_OACAC__c',
        'TLG_Household_Needs__c',
        'TLG_InternetCable__c',
        'TLG_Number_of_Adults__c',
        'TLG_Number_of_Children__c',
        'TLG_Number_of_Individuals_in_household__c',
        'TLG_Other_Assistance__c',
        'TLG_Other_Expense__c',
        'TLG_Other_Income__c',
        'TLG_Rent_Assistance__c',
        'TLG_Rent__c',
        'TLG_Repair_Car_Assistance__c',
        'TLG_SSIDisability__c',
        'TLG_SS__c',
        'TLG_TANIF__c',
        'TLG_Total_Household_Income__c',
        'TLG_Type_of_Assistance_Other__c',
        'TLG_Unemployment__c',
        'TLG_Used_Car_Assistance__c',
        'TLG_Utilities__c',
        'TLG_Utility_Assistance__c',
        'TLG_Veterans__c',
        'TLG_Wages__c',
        'Total_Household_Expense__c',
        'Total_Time_Employed_Months__c'
    };
    private static final Set<String> LANDLORD_FIELDS = new Set<String>{
        'Name', 'TLG_Street__c', 'TLG_City__c', 'TLG_State__c', 'TLG_Zip__c',
        'LandLord_Phone__c', 'TLG_Old_Address__c'
    };
    private class ReuseException extends Exception {}
    private class MemberWrite {
        Contact record;
        String role;
        String relationship;
        String customRelationship;
        Boolean isNew;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> lookupApplicant(String ssn, String assistanceType) {
        try {
            String normalized = normalizeLookupSsn(ssn);

            if (assistanceType != 'Christmas Assistance' &&
                assistanceType != 'Used Car Assistance' &&
                assistanceType != 'Year Round Assistance') {
                return response('ERROR', 'The assistance program could not be identified. Please refresh the page and try again.');
            }

            Schema.DescribeFieldResult ssnDescribe = Contact.TLG_Social_Security_Number__c.getDescribe();
            if (!ssnDescribe.isFilterable()) {
                throw new ReuseException('SSN matching is not configured correctly. Please contact Help Give Hope.');
            }

            Decimal numericSsn = Decimal.valueOf(normalized);
            List<Contact> candidates = (List<Contact>) Database.query(
                'SELECT Id, AccountId FROM Contact WHERE TLG_Social_Security_Number__c = :numericSsn ' +
                'AND (TLG_Household_Member_Status__c = \'Active\' OR TLG_Household_Member_Status__c = NULL) LIMIT 21'
            );

            if (candidates.isEmpty()) {
                return response('NOT_FOUND', 'No existing applicant was found.');
            }

            if (candidates.size() > 20) {
                return response('REVIEW_REQUIRED', 'The existing records need staff review.');
            }

            if (candidates.size() != 1) {
                return response('REVIEW_REQUIRED', 'More than one applicant record matches this SSN. Staff review is required.');
            }

            Contact match = candidates[0];
            if (match.AccountId == null) {
                return response('REVIEW_REQUIRED', 'The matching applicant is not linked to a household. Staff review is required.');
            }
            Account household = loadAccountForLookup(match.AccountId);
            List<Contact> family = loadFamilyForLookup(household.Id);
            Map<Id, Contact> familyById = new Map<Id, Contact>(family);
            Contact applicant = familyById.get(match.Id);

            if (applicant == null) {
                return response('REVIEW_REQUIRED', 'The matching applicant is no longer in this household.');
            }

            validateAgeForRole(applicant.Birthdate, 'Applicant');

            List<Map<String, Object>> children = new List<Map<String, Object>>();
            List<Map<String, Object>> adults = new List<Map<String, Object>>();

            for (Contact member : family) {
                if (member.Id == applicant.Id) continue;
                if (member.Birthdate == null || member.Birthdate < Date.newInstance(1900, 1, 1) || member.Birthdate > Date.today()) {
                    throw new ReuseException('A household member has missing or invalid birth information. Please contact Help Give Hope.');
                }

                if (member.Birthdate > Date.today().addYears(-18)) {
                    children.add(memberDto(member, household, false));
                } else {
                    adults.add(memberDto(member, household, false));
                }
            }

            Map<String, String> versions = versionMap(household, family);
            return new Map<String, Object>{
                'status' => 'FOUND',
                'message' => 'Existing household found.',
                'accountId' => household.Id,
                'recordVersions' => versions,
                'applicant' => memberDto(applicant, household, true),
                'children' => children,
                'adults' => adults
            };
        } catch (ReuseException ex) {
            return response('BLOCKED', ex.getMessage());
        } catch (Exception ignored) {
            return response('ERROR', 'The lookup could not be completed. Please try again.');
        }
    }

    /** Called only by YearRoundAssistanceFormController.save; not independently Aura enabled. */
    public static String saveReuse(YearRoundAssistanceFormController.Payload payload) {
        Savepoint sp = Database.setSavepoint();
        try {
            if (payload == null || payload.reuseAccountId == null ||
                payload.reuseRecordVersions == null || payload.reuseRecordVersions.isEmpty() ||
                payload.account == null || payload.applicant == null || payload.applicant.Id == null ||
                payload.assistanceCase == null || payload.assistanceCase.Id != null) {
                throw new ReuseException('The existing household details are incomplete. Please refresh and search again.');
            }
            if ((payload.account.Id != null && payload.account.Id != payload.reuseAccountId) ||
                (payload.applicant.AccountId != null && payload.applicant.AccountId != payload.reuseAccountId)) {
                throw new ReuseException('The application household reference is invalid. Please search again.');
            }
            if (payload.children == null) payload.children = new List<YearRoundAssistanceFormController.ChildPayload>();
            if (payload.adults == null) payload.adults = new List<YearRoundAssistanceFormController.AdultPayload>();
            if (payload.memberStatusUpdates == null) payload.memberStatusUpdates = new List<YearRoundAssistanceFormController.MemberStatusPayload>();
            if (1 + payload.children.size() + payload.adults.size() > MAX_MEMBERS) {
                throw new ReuseException('This household needs assisted processing. Please contact Help Give Hope.');
            }
            // Public form runs as a Site Guest User; this class is without sharing, so reads/writes use default system access.
            Account currentHousehold = loadAccount(payload.reuseAccountId, true);
            List<Contact> currentFamily = loadFamily(currentHousehold.Id, true);
            verifyVersions(payload.reuseRecordVersions, versionMap(currentHousehold, currentFamily));
            Map<Id, Contact> currentById = new Map<Id, Contact>(currentFamily);
            if (!currentById.containsKey(payload.applicant.Id)) {
                throw new ReuseException('The applicant no longer belongs to this household. Please contact Help Give Hope.');
            }
            // Any active member of the household may apply; the household's primary contact is switched to them below.

            Set<Id> activeSubmittedIds = new Set<Id>();
            for (YearRoundAssistanceFormController.ChildPayload row : payload.children) {
                if (row == null || row.child == null) {
                    throw new ReuseException('Review the child entries before submitting.');
                }
                if (row.child.Id != null) activeSubmittedIds.add(row.child.Id);
            }
            for (YearRoundAssistanceFormController.AdultPayload row : payload.adults) {
                if (row == null || row.adult == null) {
                    throw new ReuseException('Review the adult entries before submitting.');
                }
                if (row.adult.Id != null) activeSubmittedIds.add(row.adult.Id);
            }

            Map<Id, YearRoundAssistanceFormController.MemberStatusPayload> statusById =
                new Map<Id, YearRoundAssistanceFormController.MemberStatusPayload>();
            Set<Id> inactiveIds = new Set<Id>();

            for (YearRoundAssistanceFormController.MemberStatusPayload statusRow : payload.memberStatusUpdates) {
                if (statusRow == null || statusRow.contactId == null || statusById.containsKey(statusRow.contactId)) {
                    throw new ReuseException('The household member status selection is invalid. Please refresh and try again.');
                }
                if (statusRow.contactId == payload.applicant.Id) {
                    throw new ReuseException('The applicant status cannot be changed from this application.');
                }
                if (!currentById.containsKey(statusRow.contactId)) {
                    throw new ReuseException('A household member no longer belongs to this household. Please refresh and search again.');
                }

                String status = String.isBlank(statusRow.status) ? '' : statusRow.status.trim();
                if (status != 'Active' && status != 'Inactive') {
                    throw new ReuseException('Choose Active or Inactive for each existing household member.');
                }

                String reason = String.isBlank(statusRow.reason) ? null : statusRow.reason.trim();
                if (status == 'Inactive' && String.isBlank(reason)) {
                    throw new ReuseException('Enter a reason for every household member marked Inactive.');
                }
                if (status == 'Active') {
                    reason = null;
                }

                statusRow.status = status;
                statusRow.reason = reason;
                statusById.put(statusRow.contactId, statusRow);

                if (status == 'Inactive') {
                    inactiveIds.add(statusRow.contactId);
                }
            }

            for (Contact existingMember : currentFamily) {
                if (existingMember.Id == payload.applicant.Id) continue;
                if (!statusById.containsKey(existingMember.Id)) {
                    throw new ReuseException('Choose Active or Inactive for every existing household member.');
                }
            }

            for (Id submittedId : activeSubmittedIds) {
                if (!currentById.containsKey(submittedId)) {
                    throw new ReuseException('A household member reference is invalid. Please search again.');
                }
                YearRoundAssistanceFormController.MemberStatusPayload statusRow = statusById.get(submittedId);
                if (statusRow == null || statusRow.status != 'Active') {
                    throw new ReuseException('A household member cannot be both Active and Inactive in the same application.');
                }
            }

            for (Id inactiveId : inactiveIds) {
                if (activeSubmittedIds.contains(inactiveId)) {
                    throw new ReuseException('A household member cannot be both Active and Inactive in the same application.');
                }
            }

            Map<String, List<Contact>> byIdentity = new Map<String, List<Contact>>();
            for (Contact member : currentFamily) {
                if (inactiveIds.contains(member.Id)) continue;
                String key = identityKey(member);
                if (!byIdentity.containsKey(key)) byIdentity.put(key, new List<Contact>());
                byIdentity.get(key).add(member);
            }
            List<MemberWrite> members = new List<MemberWrite>();
            members.add(resolveMember(payload.applicant, 'Applicant', null, null, currentHousehold.Id, currentById, byIdentity));
            for (YearRoundAssistanceFormController.ChildPayload row : payload.children) {
                if (row == null) throw new ReuseException('Review the child entries before submitting.');
                members.add(resolveMember(row.child, 'Child', row.relationshipWithApplicant, null, currentHousehold.Id, currentById, byIdentity));
            }
            for (YearRoundAssistanceFormController.AdultPayload row : payload.adults) {
                if (row == null) throw new ReuseException('Review the adult entries before submitting.');
                members.add(resolveMember(row.adult, 'Adult', row.relationshipWithApplicant, row.customRelationshipWithApplicant, currentHousehold.Id, currentById, byIdentity));
            }
            rejectDuplicateMembers(members, currentById);
            validateSubmittedSsnConflicts(members, currentById, currentHousehold.Id);
            Account householdUpdate = (Account) copyAllowedFields(payload.account, Account.SObjectType, ACCOUNT_FIELDS, false);
            householdUpdate.Id = currentHousehold.Id;
            // Name, owner, primary Contact, statuses, and historical blank fields are not overwritten.
            YearRoundAssistanceFormController.prepareAccount(householdUpdate);
            Database.update(householdUpdate);
            List<Contact> inserts = new List<Contact>();
            List<Contact> updates = new List<Contact>();
            for (MemberWrite member : members) {
                if (member.isNew) inserts.add(member.record);
                else updates.add(member.record);
            }
            if (!inserts.isEmpty()) Database.insert(inserts);
            if (!updates.isEmpty()) Database.update(updates);

            if (!statusById.isEmpty()) {
                List<Contact> statusUpdates = new List<Contact>();
                for (Id memberId : statusById.keySet()) {
                    YearRoundAssistanceFormController.MemberStatusPayload statusRow = statusById.get(memberId);
                    statusUpdates.add(new Contact(
                        Id = memberId,
                        TLG_Household_Member_Status__c = statusRow.status,
                        TLG_Household_Member_Status_Reason__c = statusRow.status == 'Inactive' ? statusRow.reason : null
                    ));
                }
                Database.update(statusUpdates);
            }

            Contact applicant = members[0].record;
            // The member who applies becomes the household's primary contact (same as the new-application path).
            if (currentHousehold.npe01__One2OneContact__c != applicant.Id) {
                Database.update(new Account(Id = currentHousehold.Id, npe01__One2OneContact__c = applicant.Id));
            }
            Case application = (Case) copyAllowedFields(payload.assistanceCase, Case.SObjectType, CASE_FIELDS, true);
            application.AccountId = currentHousehold.Id;
            application.ContactId = applicant.Id;
            application.Application_Year__c = String.valueOf(Date.today().year());
            application.TLG_Number_of_Adults__c = payload.adults.size() + 1;
            application.TLG_Number_of_Children__c = payload.children.size();
            application.TLG_Number_of_Individuals_in_household__c = members.size();
            applyCaseRecordType(payload.assistanceCase, application);
            Database.insert(application);
            saveRelationships(members, applicant.Id);
            if (payload.landlord != null) {
                TLG_LandLord__c landlord = (TLG_LandLord__c) copyAllowedFields(payload.landlord, TLG_LandLord__c.SObjectType, LANDLORD_FIELDS, true);
                landlord.TLG_Contact__c = applicant.Id;
                landlord.Case__c = application.Id;
                Database.insert(landlord);
            }
            // Existing household members are either Active in this application or explicitly marked Inactive; no Contact is deleted.
            // No per-Case member snapshot or exactly-once receipt is persisted in this variant.
            Database.releaseSavepoint(sp);
            return 'OK';
        } catch (ReuseException ex) {
            Database.rollback(sp);
            return ex.getMessage();
        }  catch (Exception ex) {
            Database.rollback(sp);

            System.debug(
                LoggingLevel.ERROR,
                'HGH SAVE REUSE ERROR => ' +
                ex.getTypeName() +
                ' | ' +
                ex.getMessage() +
                ' | STACK => ' +
                ex.getStackTraceString()
            );

            return 'The application could not be saved. No partial changes were kept. Please review the form or ask Help Give Hope to check permissions and validation rules.';
        }
    }
    /** Format-only for finding an existing stored value; not identity/SSA verification. */
    @TestVisible private static String normalizeLookupSsn(String value) {
        String input = value == null ? '' : value.trim();
        if (String.isBlank(input)) {
            throw new ReuseException('Please enter your SSN.');
        }
        if (!Pattern.matches('(?:[0-9]{9}|[0-9]{3}-[0-9]{2}-[0-9]{4})', input)) {
            throw new ReuseException('Please enter all 9 digits of your SSN.');
        }
        return input.replace('-', '');
    }

    @TestVisible private static String validateAndNormalizeSsn(String value) {
        String input = value == null ? '' : value.trim();
        if (!Pattern.matches('(?:[0-9]{9}|[0-9]{3}-[0-9]{2}-[0-9]{4})', input)) {
            throw new ReuseException('Enter 9 digits, with or without hyphens (XXX-XX-XXXX).');
        }
        return input.replace('-', '');
    }
    /**
     * Number storage drops leading zeroes. SSNs have a fixed width of nine digits.
     * Restore that width for comparison/display without changing the field type.
     * Reject fractions and out-of-range data rather than silently rounding it.
     */
    @TestVisible private static String ssnDigits(Decimal value) {
        if (value == null) return null;
        Decimal whole = value.setScale(0);
        if (value < 0 || value > 999999999 || value != whole) {
            throw new ReuseException('A Social Security Number needs review. Please check the information or contact Help Give Hope.');
        }
        return String.valueOf(whole).leftPad(9, '0');
    }
    private static Decimal validatedNumericSsn(Decimal value) {
        if (value == null) return null;
        return Decimal.valueOf(validateAndNormalizeSsn(ssnDigits(value)));
    }
    @TestVisible private static String maskSsn(String value) {
        if (String.isBlank(value)) return null;
        String digits = value.replaceAll('[^0-9]', '');
        return digits.length() >= 4 ? '***-**-' + digits.right(4) : 'Stored (read only)';
    }
    private static Map<String, Object> response(String status, String message) {
        return new Map<String, Object>{'status' => status, 'message' => message};
    }
    // Lookup-only system-mode readers for the public guest path.
    // They return only the whitelisted fields used by memberDto().
    private static Account loadAccountForLookup(Id accountId) {
        List<Account> records = (List<Account>) Database.query(
            'SELECT Id, npe01__One2OneContact__c, BillingStreet, BillingCity, BillingState, '
            + 'BillingPostalCode, BillingCountry, LastModifiedDate FROM Account WHERE Id = :accountId'
        );
        if (records.isEmpty()) {
            throw new ReuseException('We could not load the saved household. Please contact Help Give Hope.');
        }
        return records[0];
    }

    private static List<Contact> loadFamilyForLookup(Id accountId) {
        List<Contact> family = (List<Contact>) Database.query(
            CONTACT_SELECT
                + 'WHERE AccountId = :accountId AND (TLG_Household_Member_Status__c = \'Active\' OR TLG_Household_Member_Status__c = NULL) '
                + 'ORDER BY CreatedDate, Id LIMIT 51'
        );
        if (family.size() > MAX_MEMBERS) {
            throw new ReuseException(
                'This household needs assisted processing. Please contact Help Give Hope.'
            );
        }
        return family;
    }

    private static Account loadAccount(Id accountId, Boolean lockRecord) {
        List<Account> records = (List<Account>) Database.query(
            'SELECT Id, npe01__One2OneContact__c, BillingStreet, BillingCity, BillingState, '
            + 'BillingPostalCode, BillingCountry, LastModifiedDate FROM Account WHERE Id = :accountId'
            + (lockRecord ? ' FOR UPDATE' : '')
        );
        if (records.isEmpty()) throw new ReuseException('The household is unavailable to this user. Please contact Help Give Hope.');
        return records[0];
    }
    private static List<Contact> loadFamily(Id accountId, Boolean lockRecords) {
        List<Contact> family = (List<Contact>) Database.query(
            CONTACT_SELECT + 'WHERE AccountId = :accountId AND (TLG_Household_Member_Status__c = \'Active\' OR TLG_Household_Member_Status__c = NULL)'
                + (lockRecords ? ' LIMIT 51 FOR UPDATE' : ' ORDER BY CreatedDate, Id LIMIT 51')
        );
        if (family.size() > MAX_MEMBERS) throw new ReuseException('This household needs assisted processing. Please contact Help Give Hope.');
        return family;
    }
    private static Map<String, Object> memberDto(Contact member, Account account, Boolean applicant) {
        return new Map<String, Object>{
            'recordId' => member.Id,
            'firstName' => member.FirstName,
            'lastName' => member.LastName,
            'email' => member.Email,
            'birthDate' => member.Birthdate,
            'gender' => member.GenderIdentity,
            'phone' => member.Phone,
            'memberStatus' => String.isBlank(member.TLG_Household_Member_Status__c) ? 'Active' : member.TLG_Household_Member_Status__c,
            'memberStatusReason' => member.TLG_Household_Member_Status_Reason__c,
            'hasSsn' => member.TLG_Social_Security_Number__c != null,
            'ssnDisplay' => maskSsn(ssnDigits(member.TLG_Social_Security_Number__c))
        };
    }
    private static String snapshotDigest(SObject record) {
        Map<String, Object> fields = new Map<String, Object>();
        fields.putAll(record.getPopulatedFieldsAsMap());

        // Never send even an unkeyed hash derived from SSN to a browser.
        fields.remove(SSN_FIELD);

        // Ignore system/audit fields so background automation does not create
        // false stale-form errors when no real household data changed.
        fields.remove('LastModifiedDate');
        fields.remove('SystemModstamp');
        fields.remove('LastModifiedById');
        fields.remove('CreatedDate');
        fields.remove('CreatedById');

        List<String> names = new List<String>(fields.keySet());
        names.sort();

        List<Object> snapshot = new List<Object>();
        for (String name : names) {
            snapshot.add(name);
            snapshot.add(fields.get(name));
        }

        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(JSON.serialize(snapshot)))
        );
    }
    private static Map<String, String> versionMap(Account account, List<Contact> family) {
        Map<String, String> versions = new Map<String, String>{
            String.valueOf(account.Id) => snapshotDigest(account)
        };
        for (Contact member : family) versions.put(String.valueOf(member.Id), snapshotDigest(member));
        return versions;
    }
    private static void verifyVersions(Map<String, String> saved, Map<String, String> currentVersions) {
        // The client can edit this snapshot; authorization is independently enforced above.
        // This detects ordinary stale forms, but is not a security token or replay guarantee.
        if (saved.size() != currentVersions.size()) {
            throw new ReuseException('Household membership changed while this form was open. Please refresh and search again.');
        }
        for (String recordId : currentVersions.keySet()) {
            if (!saved.containsKey(recordId) || String.valueOf(saved.get(recordId)) != currentVersions.get(recordId)) {
                throw new ReuseException('Household details changed while this form was open. Please refresh and search again to avoid overwriting newer information.');
            }
        }
    }
    private static String cleanName(String value) {
        return value == null ? '' : value.trim().toLowerCase().replaceAll('\\s+', ' ');
    }
    private static String identityKey(Contact record) {
        return cleanName(record.FirstName) + '|' + cleanName(record.LastName) + '|' + String.valueOf(record.Birthdate);
    }
    private static void validateAgeForRole(Date birthdate, String role) {
        if (birthdate == null || birthdate < Date.newInstance(1900, 1, 1) || birthdate > Date.today()) {
            throw new ReuseException('Enter a valid date of birth for each household member.');
        }
        Boolean isAdult = birthdate <= Date.today().addYears(-18);
        if ((role == 'Child' && isAdult) || (role != 'Child' && !isAdult)) {
            throw new ReuseException('Check the dates of birth. Children must be under 18 and applicants/adults must be 18 or older.');
        }
    }
    private static MemberWrite resolveMember(Contact incoming, String role, String relationship,
        String customRelationship, Id accountId, Map<Id, Contact> existingById, Map<String, List<Contact>> byIdentity) {
        if (incoming == null || String.isBlank(incoming.FirstName) || String.isBlank(incoming.LastName)) {
            throw new ReuseException('Enter first and last names for every household member.');
        }
        if (incoming.AccountId != null && incoming.AccountId != accountId) {
            throw new ReuseException('A household member reference is invalid. Please search again.');
        }
        validateAgeForRole(incoming.Birthdate, role);
        if ((role == 'Applicant' && String.isBlank(incoming.Email)) ||
            (String.isNotBlank(incoming.Email) && !Pattern.matches('[^\\s@]+@[^\\s@]+\\.[^\\s@]+', incoming.Email.trim()))) {
            throw new ReuseException('Enter a valid email address for the applicant and check any member email addresses.');
        }
        Contact existing;
        if (incoming.Id != null) {
            existing = existingById.get(incoming.Id);
            if (existing == null) throw new ReuseException('A household member reference is invalid. Please search again.');
        } else {
            // New rows are not matched by name or date of birth.
            // SSN is the only duplicate key for public household reuse.
        }
        Contact record = (Contact) copyAllowedFields(incoming, Contact.SObjectType, CONTACT_FIELDS, existing == null);
        if (existing != null) {
            // Only selected prefill fields may be cleared explicitly; absent financial fields are preserved.
            Map<String, Object> submitted = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(incoming));
            for (String fieldName : EDITABLE_PREFILL_FIELDS) if (submitted.containsKey(fieldName)) record.put(fieldName, incoming.get(fieldName));
            record.Id = existing.Id;
            if (existing.TLG_Social_Security_Number__c != null) {
                Decimal submittedSsn = incoming.TLG_Social_Security_Number__c;
                if (submittedSsn != null && submittedSsn != existing.TLG_Social_Security_Number__c) {
                    throw new ReuseException('An existing Social Security Number cannot be changed through this form.');
                }
                // Remove the field completely so a stored SSN is never overwritten by this form.
                Set<String> withoutSsn = CONTACT_FIELDS.clone();
                withoutSsn.remove(SSN_FIELD);
                Contact safeRecord = (Contact) copyAllowedFields(record, Contact.SObjectType, withoutSsn, true);
                safeRecord.Id = existing.Id;
                record = safeRecord;
            } else if (record.TLG_Social_Security_Number__c != null) {
                record.TLG_Social_Security_Number__c = validatedNumericSsn(record.TLG_Social_Security_Number__c);
            }
        } else {
            record.AccountId = accountId;
            if (record.TLG_Social_Security_Number__c != null) {
                record.TLG_Social_Security_Number__c = validatedNumericSsn(record.TLG_Social_Security_Number__c);
            }
        }
        if (existing == null && record.TLG_Social_Security_Number__c != null) {
            for (Contact savedMember : existingById.values()) {
                if (savedMember.TLG_Social_Security_Number__c != null &&
                    record.TLG_Social_Security_Number__c == savedMember.TLG_Social_Security_Number__c) {
                    throw new ReuseException('The SSN belongs to an existing household member. Use that loaded member entry or contact Help Give Hope.');
                }
            }
        }
        // New household members are active by definition. The public UI does not
        // show the status control until the Contact exists in Salesforce.
        if (existing == null) {
            record.TLG_Household_Member_Status__c = 'Active';
            record.TLG_Household_Member_Status_Reason__c = null;
        }

        // TLG_Age__c is not writable in this org. Save Birthdate only.
        // Age validation is calculated from Birthdate in validateAgeForRole().
        MemberWrite result = new MemberWrite();
        result.record = record;
        result.role = role;
        result.relationship = relationship;
        result.customRelationship = customRelationship;
        result.isNew = existing == null;
        return result;
    }
    private static void rejectDuplicateMembers(List<MemberWrite> members, Map<Id, Contact> existingById) {
        Set<Id> ids = new Set<Id>();
        for (MemberWrite member : members) {
            if (member.record.Id != null && ids.contains(member.record.Id)) {
                throw new ReuseException('The same household member is listed more than once. Remove duplicate household members.');
            }
            if (member.record.Id != null) ids.add(member.record.Id);
        }
    }
    private static void validateSubmittedSsnConflicts(List<MemberWrite> members, Map<Id, Contact> existingById, Id householdId) {
        Set<String> submittedSsns = new Set<String>();
        Set<Decimal> submittedSsnValues = new Set<Decimal>();
        Map<Id, String> allowedSsnByContactId = new Map<Id, String>();

        for (MemberWrite member : members) {
            Decimal ssn = member.record.TLG_Social_Security_Number__c;
            if (ssn == null && member.record.Id != null && existingById.containsKey(member.record.Id)) {
                ssn = existingById.get(member.record.Id).TLG_Social_Security_Number__c;
            }
            if (ssn == null) {
                throw new ReuseException('Enter a Social Security Number for every applicant, adult, and child.');
            }

            String canonical = ssnDigits(ssn);
            if (submittedSsns.contains(canonical)) {
                throw new ReuseException('Two listed household members have the same Social Security Number. Each household member must have a unique SSN.');
            }
            submittedSsns.add(canonical);
            submittedSsnValues.add(Decimal.valueOf(canonical));
            if (member.record.Id != null) {
                allowedSsnByContactId.put(member.record.Id, canonical);
            }
        }

        if (submittedSsnValues.isEmpty()) return;

        List<Contact> matches = (List<Contact>) Database.query(
            'SELECT Id, AccountId, TLG_Social_Security_Number__c FROM Contact WHERE TLG_Social_Security_Number__c IN :submittedSsnValues'
        );

        for (Contact match : matches) {
            String canonical = ssnDigits(match.TLG_Social_Security_Number__c);
            if (allowedSsnByContactId.containsKey(match.Id) && allowedSsnByContactId.get(match.Id).equals(canonical)) {
                continue;
            }
            throw new ReuseException('This SSN already belongs to another Contact. Please contact Help Give Hope before submitting.');
        }
    }
    private static SObject copyAllowedFields(SObject incoming, Schema.SObjectType targetType, Set<String> allowed, Boolean includeNulls) {
        SObject result = targetType.newSObject();
        Map<String, Object> submitted = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(incoming));
        for (String fieldName : allowed) {
            if (submitted.containsKey(fieldName) && (includeNulls || incoming.get(fieldName) != null)) {
                result.put(fieldName, incoming.get(fieldName));
            }
        }
        return result;
    }
    private static void applyCaseRecordType(Case incoming, Case result) {
        SObject relationship = incoming.getSObject('RecordType');
        if (relationship == null) return;
        String developerName = (String) relationship.get('DeveloperName');
        Set<String> allowedRecordTypes = new Set<String>{'Christmas_Application', 'Used_Car_Application', 'Assistance_Application'};
        if (!allowedRecordTypes.contains(developerName)) {
            throw new ReuseException('The application type is invalid. Please reopen the correct form.');
        }
        result.putSObject('RecordType', new RecordType(DeveloperName = developerName));
        YearRoundAssistanceFormController.normalizeCaseRecordType(result);
    }
    private static void saveRelationships(List<MemberWrite> members, Id applicantId) {
        Set<Id> relatedIds = new Set<Id>();
        for (MemberWrite member : members) if (member.role != 'Applicant') relatedIds.add(member.record.Id);
        if (relatedIds.isEmpty()) return;
        Map<Id, npe4__Relationship__c> existing = new Map<Id, npe4__Relationship__c>();
        for (npe4__Relationship__c relationship : [
            SELECT Id, npe4__RelatedContact__c FROM npe4__Relationship__c
            WHERE npe4__Contact__c = :applicantId
            AND npe4__RelatedContact__c IN :relatedIds
        ]) {
            if (existing.containsKey(relationship.npe4__RelatedContact__c)) {
                throw new ReuseException('Duplicate household relationships need staff review before this application can be saved.');
            }
            existing.put(relationship.npe4__RelatedContact__c, relationship);
        }
        List<npe4__Relationship__c> inserts = new List<npe4__Relationship__c>();
        List<npe4__Relationship__c> updates = new List<npe4__Relationship__c>();
        for (MemberWrite member : members) {
            if (member.role == 'Applicant') continue;
            if (String.isBlank(member.relationship)) throw new ReuseException('Select the relationship to the applicant for every child and adult.');
            if (member.role == 'Adult' && member.relationship == 'Other' && String.isBlank(member.customRelationship)) {
                throw new ReuseException('Describe the adult relationship when Other is selected.');
            }
            npe4__Relationship__c relationship = new npe4__Relationship__c();
            if (existing.containsKey(member.record.Id)) relationship.Id = existing.get(member.record.Id).Id;
            else {
                relationship.npe4__Contact__c = applicantId;
                relationship.npe4__RelatedContact__c = member.record.Id;
            }
            if (member.role == 'Child') relationship.npe4__Type__c = member.relationship;
            else {
                relationship.Adult_Type__c = member.relationship;
                relationship.Adult_Type_Custom__c = member.customRelationship;
            }
            if (relationship.Id == null) inserts.add(relationship);
            else updates.add(relationship);
        }
        if (!inserts.isEmpty()) Database.insert(inserts);
        if (!updates.isEmpty()) Database.update(updates);
    }
}