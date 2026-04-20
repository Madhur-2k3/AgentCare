public with sharing class OncoGetAppointmentReasons {

    public class ReasonResponse {
        @InvocableVariable(description='Formatted list of available appointment reasons with descriptions')
        public String reasonsList;
        @InvocableVariable(description='Total number of reasons available')
        public Integer totalReasons;
    }

    @InvocableMethod(label='Get Appointment Reasons' description='Retrieve active appointment reasons for patient self-scheduling')
    public static List<ReasonResponse> getReasons(List<String> dummyInput) {
        List<ReasonResponse> responses = new List<ReasonResponse>();
        ReasonResponse res = new ReasonResponse();

        List<AppointmentReason> reasons = [
            SELECT Id, Name, Description, DefaultWorkTypeId, DefaultWorkType.Name,
                   DefaultWorkType.EstimatedDuration
            FROM AppointmentReason
            WHERE IsActive = true
            AND Visibility = 'PATIENT_SELF_SCHEDULING'
            ORDER BY Name
        ];
        System.debug('reasons: ' + JSON.serializePretty(reasons));
        String formatted = '';
        Integer count = 0;
        for (AppointmentReason ar : reasons) {
            count++;
            formatted += count + '. ' + ar.Name + ' — ' + ar.Description;
            formatted += ' (Duration: ~' + ar.DefaultWorkType.EstimatedDuration + ' min)';
            formatted += '\n';
        }
        System.debug('formatted: ' + formatted);
        res.reasonsList = formatted;
        System.debug('count: ' + count);
        res.totalReasons = count;
        System.debug('res: ' + res);
        responses.add(res);
        System.debug('responses: ' + responses);
        return responses;
    }
}
