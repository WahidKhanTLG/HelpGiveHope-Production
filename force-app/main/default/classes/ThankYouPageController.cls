public without sharing class ThankYouPageController {
    public String title { get; private set; }
    public String subtitle { get; private set; }
    public String message { get; private set; }
    public String statusBoxMessage { get; private set; }
    public String footerText { get; private set; }
    public String iconText { get; private set; }
    public String cardVariantClass { get; private set; }

    public ThankYouPageController() {
        setContent(
            'EMAIL VERIFICATION',
            'We are processing your request',
            'Please wait while we validate your email verification request.',
            'If this page does not refresh correctly, please reopen the verification link from your email.',
            'Help Give Hope',
            '...',
            'info'
        );
    }

    public PageReference verify() {
        String caseIdParam = ApexPages.currentPage().getParameters().get('id');

        if (String.isBlank(caseIdParam)) {
            setInvalidContent();
            return null;
        }

        Id caseId;
        try {
            caseId = (Id) caseIdParam;
        } catch (Exception ex) {
            setInvalidContent();
            return null;
        }

        if (!String.valueOf(caseId).startsWith(Case.SObjectType.getDescribe().getKeyPrefix())) {
            setInvalidContent();
            return null;
        }

        List<Case> caseList = [
            SELECT Id, Status
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (caseList.isEmpty()) {
            setInvalidContent();
            return null;
        }

        Case caseRecord = caseList[0];

        if (caseRecord.Status == 'New') {
            caseRecord.Status = 'Escalated';
            update caseRecord;
            setVerifiedContent();
            return null;
        }

        if (caseRecord.Status == 'Escalated') {
            setAlreadyVerifiedContent();
            return null;
        }

        setNoActionNeededContent(caseRecord.Status);
        return null;
    }

    private void setVerifiedContent() {
        setContent(
            'EMAIL VERIFIED',
            'Your email address has been confirmed successfully',
            'Thank you for confirming your email address for your Christmas Assistance application.',
            'Your verification has been recorded successfully. Our team will continue reviewing your application.',
            'Helping families in need with compassion and care',
            '✓',
            'success'
        );
    }

    private void setAlreadyVerifiedContent() {
        setContent(
            'ALREADY VERIFIED',
            'No further action is required',
            'This email address has already been verified for your application.',
            'Your information is already on file and no additional update was needed.',
            'Helping families in need with compassion and care',
            'i',
            'info'
        );
    }

    private void setNoActionNeededContent(String currentStatus) {
        setContent(
            'NO UPDATE NEEDED',
            'Your request was received',
            'We found your application, but no status update was required at this stage.',
            'Your information is already on file and no additional update was needed.',
            'Helping families in need with compassion and care',
            'i',
            'warning'
        );
    }

    private void setInvalidContent() {
        setContent(
            'INVALID REQUEST',
            'We could not process this verification link',
            'The verification link is missing information, invalid, or the related application could not be found.',
            'Please contact Help Give Hope if you believe this is an error.',
            'Helping families in need with compassion and care',
            '!',
            'warning'
        );
    }

    private void setContent(
        String pageTitle,
        String pageSubtitle,
        String pageMessage,
        String pageStatusBoxMessage,
        String pageFooterText,
        String pageIconText,
        String pageCardVariantClass
    ) {
        title = pageTitle;
        subtitle = pageSubtitle;
        message = pageMessage;
        statusBoxMessage = pageStatusBoxMessage;
        footerText = pageFooterText;
        iconText = pageIconText;
        cardVariantClass = pageCardVariantClass;
    }
}