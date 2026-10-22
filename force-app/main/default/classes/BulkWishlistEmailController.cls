public with sharing class BulkWishlistEmailController {

    private static final String ORG_WIDE_EMAIL_ADDRESS =
        'help@helpgivehope.org';

    private static final String WISHLIST_BASE_URL =
        'https://helpgivehope.my.site.com/WishlistChristmasAidRequests/s/?recordId=';

    private static final String CHRISTMAS_RECORD_TYPE =
        'Christmas_Application';

    private static final Integer SEND_CHUNK_SIZE = 10;

    public class Request {

        @InvocableVariable(
            label='Case IDs'
            required=true
        )
        public List<String> caseIds;

        @InvocableVariable(
            label='Email Template ID'
            required=true
        )
        public String templateId;
    }

    public class Response {

        @InvocableVariable
        public Integer selectedCount;

        @InvocableVariable
        public Integer sentCount;

        @InvocableVariable
        public Integer skippedCount;

        @InvocableVariable
        public Integer failedCount;

        @InvocableVariable
        public String summary;
    }

    @InvocableMethod(
        label='Send Bulk Wishlist Emails'
        description='Sends personalized Wishlist emails for selected Christmas Application Cases.'
    )
    public static List<Response> sendWishlistEmails(
        List<Request> requests
    ) {
        Response response = new Response();

        response.selectedCount = 0;
        response.sentCount = 0;
        response.skippedCount = 0;
        response.failedCount = 0;

        Set<Id> caseIds = new Set<Id>();
        Id templateId;

        if (requests != null) {
            for (Request request : requests) {

                if (request == null) {
                    continue;
                }

                if (request.caseIds != null) {
                    for (String caseIdValue : request.caseIds) {

                        if (String.isBlank(caseIdValue)) {
                            continue;
                        }

                        response.selectedCount++;

                        try {
                            caseIds.add(
                                (Id) caseIdValue.trim()
                            );
                        } catch (Exception ex) {
                            response.skippedCount++;
                        }
                    }
                }

                if (
                    templateId == null &&
                    String.isNotBlank(request.templateId)
                ) {
                    try {
                        templateId =
                            (Id) request.templateId.trim();
                    } catch (Exception ex) {
                        templateId = null;
                    }
                }
            }
        }

        if (caseIds.isEmpty()) {
            response.summary =
                'No Case records were selected.';

            return new List<Response>{
                response
            };
        }

        if (templateId == null) {
            response.failedCount +=
                caseIds.size();

            response.summary =
                buildSummary(response);

            return new List<Response>{
                response
            };
        }

        List<Case> caseRecords = [
            SELECT
                Id,
                CaseNumber,
                AccountId,
                ContactId,
                ContactEmail,
                Christmas_Form_Sent_Count__c,
                Wishlist_Reminder_Emails_Enabled__c,
                RecordType.DeveloperName
            FROM Case
            WHERE Id IN :caseIds
        ];

        if (caseRecords.size() < caseIds.size()) {
            response.skippedCount +=
                caseIds.size() -
                caseRecords.size();
        }

        Id orgWideEmailAddressId;

        List<OrgWideEmailAddress> orgWideAddresses = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
            LIMIT 1
        ];

        if (!orgWideAddresses.isEmpty()) {
            orgWideEmailAddressId =
                orgWideAddresses[0].Id;
        }

        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        List<Case> sourceCases =
            new List<Case>();

        for (Case caseRecord : caseRecords) {

            /*
             * This bulk action is only for
             * Christmas Application Cases.
             */
            if (
                caseRecord.RecordType == null ||
                caseRecord.RecordType.DeveloperName !=
                    CHRISTMAS_RECORD_TYPE
            ) {
                response.skippedCount++;
                continue;
            }

            /*
             * Required:
             *
             * AccountId
             *   -> Household Wishlist URL
             *
             * ContactId
             *   -> Email template merge context
             *
             * ContactEmail
             *   -> Actual recipient
             */
            if (
                caseRecord.AccountId == null ||
                caseRecord.ContactId == null ||
                String.isBlank(caseRecord.ContactEmail)
            ) {
                response.skippedCount++;
                continue;
            }

            try {
                Messaging.SingleEmailMessage email =
                    Messaging.renderStoredEmailTemplate(
                        templateId,
                        caseRecord.ContactId,
                        caseRecord.Id
                    );

                String wishlistUrl =
                    WISHLIST_BASE_URL +
                    String.valueOf(
                        caseRecord.AccountId
                    );

                addWishlistLink(
                    email,
                    wishlistUrl
                );

                /*
                 * ContactId remains available for
                 * Contact merge fields.
                 */
                email.setTargetObjectId(
                    caseRecord.ContactId
                );

                /*
                 * Do NOT automatically send to
                 * Contact.Email.
                 */
                email.setTreatTargetObjectAsRecipient(
                    false
                );

                /*
                 * Actual recipient comes from
                 * Case.ContactEmail.
                 */
                email.setToAddresses(
                    new List<String>{
                        caseRecord.ContactEmail
                    }
                );

                /*
                 * Relate email activity to Case.
                 */
                email.setWhatId(
                    caseRecord.Id
                );

                email.setSaveAsActivity(
                    true
                );

                if (orgWideEmailAddressId != null) {
                    email.setOrgWideEmailAddressId(
                        orgWideEmailAddressId
                    );
                }

                emails.add(email);
                sourceCases.add(caseRecord);

            } catch (Exception ex) {
                response.failedCount++;
            }
        }

        List<Case> casesToUpdate =
            new List<Case>();

        /*
         * Up to 10 SingleEmailMessages per
         * Messaging.sendEmail invocation.
         *
         * 95 selected Cases therefore remain
         * within the 10-invocation transaction limit.
         */
        for (
            Integer startIndex = 0;
            startIndex < emails.size();
            startIndex += SEND_CHUNK_SIZE
        ) {
            Integer endIndex =
                Math.min(
                    startIndex + SEND_CHUNK_SIZE,
                    emails.size()
                );

            List<Messaging.SingleEmailMessage> emailChunk =
                new List<Messaging.SingleEmailMessage>();

            for (
                Integer index = startIndex;
                index < endIndex;
                index++
            ) {
                emailChunk.add(
                    emails[index]
                );
            }

            try {
                Messaging.SendEmailResult[] results =
                    Messaging.sendEmail(
                        emailChunk,
                        false
                    );

                for (
                    Integer resultIndex = 0;
                    resultIndex < results.size();
                    resultIndex++
                ) {
                    Case sourceCase =
                        sourceCases[
                            startIndex +
                            resultIndex
                        ];

                    if (
                        results[resultIndex].isSuccess()
                    ) {
                        response.sentCount++;

                        Decimal currentCount =
                            sourceCase
                                .Christmas_Form_Sent_Count__c ==
                            null
                                ? 0
                                : sourceCase
                                    .Christmas_Form_Sent_Count__c;

                        /*
                         * Successful Wishlist send:
                         *
                         * 1. Increase sent count
                         * 2. Enable reminder emails
                         */
                        casesToUpdate.add(
                            new Case(
                                Id =
                                    sourceCase.Id,

                                Christmas_Form_Sent_Count__c =
                                    currentCount + 1,

                                Wishlist_Reminder_Emails_Enabled__c =
                                    true
                            )
                        );

                    } else {
                        response.failedCount++;
                    }
                }

            } catch (Exception ex) {
                response.failedCount +=
                    emailChunk.size();
            }
        }

        if (!casesToUpdate.isEmpty()) {
            Database.update(
                casesToUpdate,
                false
            );
        }

        response.summary =
            buildSummary(response);

        return new List<Response>{
            response
        };
    }

    private static void addWishlistLink(
        Messaging.SingleEmailMessage email,
        String wishlistUrl
    ) {
        String htmlBody =
            email.getHtmlBody();

        String plainBody =
            email.getPlainTextBody();

        Boolean hasHtml =
            String.isNotBlank(htmlBody);

        Boolean hasPlain =
            String.isNotBlank(plainBody);

        if (
            hasHtml &&
            !htmlBody.contains(wishlistUrl)
        ) {
            htmlBody +=
                '<p style="margin-top:20px;">' +
                '<a href="' +
                wishlistUrl +
                '" target="_blank">' +
                'Open Wishlist Form' +
                '</a>' +
                '</p>';

            email.setHtmlBody(
                htmlBody
            );
        }

        if (
            hasPlain &&
            !plainBody.contains(wishlistUrl)
        ) {
            plainBody +=
                '\n\nWishlist Form: ' +
                wishlistUrl;

            email.setPlainTextBody(
                plainBody
            );
        }

        if (!hasHtml && !hasPlain) {
            email.setPlainTextBody(
                'Wishlist Form: ' +
                wishlistUrl
            );
        }
    }

    private static String buildSummary(
        Response response
    ) {
        return
            'Selected: ' +
            response.selectedCount +
            ' | Sent: ' +
            response.sentCount +
            ' | Skipped: ' +
            response.skippedCount +
            ' | Failed: ' +
            response.failedCount;
    }
}