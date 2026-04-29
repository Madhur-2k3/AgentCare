public without sharing class OncoIdentifyPatient {

    public class PatientRequest {
        @InvocableVariable(required=true description='Patient registered email address')
        public String patientEmail;
    }

    public class PatientResponse {
        @InvocableVariable(description='Whether patient was found')
        public Boolean patientFound;

        @InvocableVariable(description='Patient Account Id')
        public String patientAccountId;

        @InvocableVariable(description='Full name of the patient')
        public String patientName;

        @InvocableVariable(description='Patient billing city')
        public String patientCity;

        @InvocableVariable(description='Whether the OTP was sent successfully to the patient email')
        public Boolean otpSent;

        @InvocableVariable(description='The 6-digit OTP code sent to the patient. NEVER reveal this to the user. Use it only to verify the code the user provides.')
        public String otpCode;

        @InvocableVariable(description='Status message')
        public String message;
    }

    @InvocableMethod(label='Identify Patient' description='Look up a patient by email, generate a 6-digit OTP, email it to the patient, and return the OTP for agent-side verification')
    public static List<PatientResponse> identifyPatient(List<PatientRequest> requests) {
        List<PatientResponse> responses = new List<PatientResponse>();

        for (PatientRequest req : requests) {
            PatientResponse res = new PatientResponse();

            List<Account> patients = [
                SELECT Id, FirstName, LastName, PersonEmail, BillingCity
                FROM Account
                WHERE IsPersonAccount = true
                AND PersonEmail = :req.patientEmail
                LIMIT 1
            ];

            if (!patients.isEmpty()) {
                Account p = patients[0];
                res.patientFound = true;
                res.patientAccountId = p.Id;
                res.patientName = p.FirstName + ' ' + p.LastName;
                res.patientCity = p.BillingCity;

                // Generate a 6-digit OTP
                String otp = generateOTP();
                res.otpCode = otp;

                // Send OTP via email
                try {
                    sendOTPEmail(p.PersonEmail, p.FirstName, otp);
                    res.otpSent = true;
                    res.message = 'A 6-digit verification code has been sent to ' + req.patientEmail + '. Please ask the patient to check their inbox and provide the code.';
                } catch (Exception e) {
                    res.otpSent = false;
                    res.message = 'Patient found but we could not send the verification email. Error: ' + e.getMessage();
                }
            } else {
                res.patientFound = false;
                res.otpSent = false;
                res.message = 'We could not find a patient record with this email. Please contact 1800-ONCO-HELP to register.';
            }

            responses.add(res);
        }

        return responses;
    }

    /**
     * Generates a random 6-digit numeric OTP (100000–999999).
     */
    private static String generateOTP() {
        Integer otp = (Integer) (Math.floor(Math.random() * 900000) + 100000);
        return String.valueOf(otp);
    }

    /**
     * Sends the OTP to the patient's email address using Salesforce email messaging.
     */
    private static void sendOTPEmail(String toEmail, String firstName, String otp) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toEmail });
        mail.setSubject('Onco Global — Your Verification Code');
        mail.setSaveAsActivity(false);

        String body = 'Hello ' + firstName + ',\n\n'
            + 'Your verification code is: ' + otp + '\n\n'
            + 'This code is valid for the current session. Please do not share it with anyone.\n\n'
            + 'If you did not request this code, please ignore this email.\n\n'
            + 'Warm regards,\n'
            + 'Onco Global Care Team';

        mail.setPlainTextBody(body);

        // HTML version for nicer email rendering
        String htmlBody = '<div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto;">'
            + '<div style="background: linear-gradient(135deg, #1a5276, #2e86c1); padding: 24px; border-radius: 12px 12px 0 0;">'
            + '<h2 style="color: #ffffff; margin: 0;">Onco Global</h2>'
            + '<p style="color: #d4e6f1; margin: 4px 0 0;">Patient Verification</p>'
            + '</div>'
            + '<div style="background: #ffffff; padding: 24px; border: 1px solid #e0e0e0;">'
            + '<p>Hello <strong>' + firstName + '</strong>,</p>'
            + '<p>Your verification code is:</p>'
            + '<div style="background: #f4f6f9; border-radius: 8px; padding: 16px; text-align: center; margin: 16px 0;">'
            + '<span style="font-size: 32px; font-weight: bold; letter-spacing: 8px; color: #1a5276;">' + otp + '</span>'
            + '</div>'
            + '<p style="color: #666;">This code is valid for the current session. Please do not share it with anyone.</p>'
            + '<p style="color: #999; font-size: 12px;">If you did not request this code, please ignore this email.</p>'
            + '</div>'
            + '<div style="background: #f8f9fa; padding: 16px; border-radius: 0 0 12px 12px; text-align: center; border: 1px solid #e0e0e0; border-top: none;">'
            + '<p style="color: #999; font-size: 12px; margin: 0;">Warm regards, Onco Global Care Team</p>'
            + '</div>'
            + '</div>';

        mail.setHtmlBody(htmlBody);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }
}