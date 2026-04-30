public without sharing class OncoIdentifyPatientByPhone {

    public class PatientRequest {
        @InvocableVariable(required=true description='Patient phone number captured from the voice call (ANI)')
        public String patientPhone;
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

        @InvocableVariable(description='Status message')
        public String message;
    }

    @InvocableMethod(label='Identify Patient By Phone' description='Look up a patient by their phone number and return their details if found')
    public static List<PatientResponse> identifyPatient(List<PatientRequest> requests) {
        List<PatientResponse> responses = new List<PatientResponse>();

        for (PatientRequest req : requests) {
            PatientResponse res = new PatientResponse();

            System.debug('>>> [OncoIdentifyPatientByPhone] RAW patientPhone received: "' + req.patientPhone + '"');

            // Normalize the incoming phone number for flexible matching
            String normalizedPhone = normalizePhone(req.patientPhone);

            System.debug('>>> [OncoIdentifyPatientByPhone] NORMALIZED phone: "' + normalizedPhone + '"');

            // Also try stripping to just digits for broader matching
            String digitsOnly = String.isBlank(req.patientPhone) ? '' : req.patientPhone.replaceAll('[^0-9]', '');
            // Strip country code (91 for India) to get the local 10-digit number
            String strippedPhone = digitsOnly;
            if (strippedPhone.startsWith('91') && strippedPhone.length() > 10) {
                strippedPhone = strippedPhone.substring(2);
            }
            System.debug('>>> [OncoIdentifyPatientByPhone] DIGITS ONLY: "' + digitsOnly + '"');
            System.debug('>>> [OncoIdentifyPatientByPhone] STRIPPED (no country code): "' + strippedPhone + '"');

            List<Account> patients = [
                SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone, Phone, BillingCity
                FROM Account
                WHERE IsPersonAccount = true
                AND (PersonMobilePhone = :normalizedPhone
                     OR Phone = :normalizedPhone
                     OR PersonMobilePhone = :req.patientPhone
                     OR Phone = :req.patientPhone
                     OR PersonMobilePhone = :digitsOnly
                     OR Phone = :digitsOnly
                     OR PersonMobilePhone = :strippedPhone
                     OR Phone = :strippedPhone)
                LIMIT 1
            ];

            System.debug('>>> [OncoIdentifyPatientByPhone] Query returned ' + patients.size() + ' record(s)');

            if (!patients.isEmpty()) {
                Account p = patients[0];
                System.debug('>>> [OncoIdentifyPatientByPhone] MATCHED Account: ' + p.Id + ' | Name: ' + p.FirstName + ' ' + p.LastName + ' | PersonMobilePhone: ' + p.PersonMobilePhone + ' | Phone: ' + p.Phone);
                res.patientFound = true;
                res.patientAccountId = p.Id;
                res.patientName = p.FirstName + ' ' + p.LastName;
                res.patientCity = p.BillingCity;
                res.message = 'Patient verified successfully via phone number.';
            } else {
                // DEBUG: dump what phone numbers exist in the system for comparison
                List<Account> allPatients = [
                    SELECT Id, FirstName, LastName, PersonMobilePhone, Phone
                    FROM Account
                    WHERE IsPersonAccount = true
                    AND (PersonMobilePhone != null OR Phone != null)
                    LIMIT 5
                ];
                for (Account a : allPatients) {
                    System.debug('>>> [OncoIdentifyPatientByPhone] EXISTING record — Id: ' + a.Id + ' | PersonMobilePhone: "' + a.PersonMobilePhone + '" | Phone: "' + a.Phone + '"');
                }

                res.patientFound = false;
                res.message = 'We could not find a patient record associated with this phone number. Received phone: ' + req.patientPhone + ' | Normalized: ' + normalizedPhone + ' | Digits: ' + digitsOnly;
            }

            responses.add(res);
        }

        return responses;
    }

    /**
     * Normalizes a phone number by stripping all non-digit characters
     * and prepending a country code if missing.
     * Telephony providers typically send E.164 format (e.g., +919876543210).
     */
    private static String normalizePhone(String phone) {
        if (String.isBlank(phone)) return '';
        // Strip everything except digits and leading +
        String cleaned = phone.replaceAll('[^0-9+]', '');
        // If it starts with +, keep it; otherwise prepend +91 (India)
        if (!cleaned.startsWith('+')) {
            cleaned = '+91' + cleaned;
        }
        return cleaned;
    }
}
