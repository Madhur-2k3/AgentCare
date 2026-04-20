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
        @InvocableVariable(description='Status message')
        public String message;
    }
    @InvocableMethod(label='Identify Patient' description='Look up a patient by email in Person Accounts')
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
                res.message = 'Welcome back, ' + p.FirstName + '! We found your records.';
            } else {
                res.patientFound = false;
                res.message = 'We could not find a patient record with this email. Please contact 1800-ONCO-HELP to register.';
            }
            responses.add(res);
        }
        return responses;
    }
}