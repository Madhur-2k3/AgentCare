public without sharing class OncoCancelAppointment {

    public class CancelRequest {
        @InvocableVariable(required=true description='The ServiceAppointment Id to cancel')
        public String appointmentId;
        @InvocableVariable(description='Reason for cancellation provided by the patient')
        public String cancellationReason;
    }

    public class CancelResponse {
        @InvocableVariable(description='Whether cancellation was successful')
        public Boolean success;
        @InvocableVariable(description='Cancellation confirmation message')
        public String confirmationMessage;
    }

    @InvocableMethod(label='Cancel Appointment' description='Cancel an existing scheduled appointment')
    public static List<CancelResponse> cancelAppointment(List<CancelRequest> requests) {
        List<CancelResponse> responses = new List<CancelResponse>();

        for (CancelRequest req : requests) {
            CancelResponse res = new CancelResponse();

            try {
                // Get the appointment details
                List<ServiceAppointment> apptList = [
                    SELECT Id, Subject, Status, SchedStartTime, SchedEndTime,
                           WorkType.Name, ServiceTerritory.Name, ServiceTerritory.Description,
                           ParentRecordId, Description
                    FROM ServiceAppointment
                    WHERE Id = :req.appointmentId
                    LIMIT 1
                ];

                if (apptList.isEmpty()) {
                    res.success = false;
                    res.confirmationMessage = 'Appointment not found. Please verify the Appointment ID.';
                    responses.add(res);
                    continue;
                }

                ServiceAppointment appt = apptList[0];

                // Only scheduled appointments can be canceled
                if (appt.Status != 'Scheduled') {
                    res.success = false;
                    res.confirmationMessage = 'This appointment cannot be canceled because its status is "'
                        + appt.Status + '". Only scheduled appointments can be canceled.';
                    responses.add(res);
                    continue;
                }

                // Get doctor name
                String doctorName = 'your doctor';
                List<AssignedResource> arList = [
                    SELECT ServiceResource.Name
                    FROM AssignedResource
                    WHERE ServiceAppointmentId = :appt.Id
                    LIMIT 1
                ];
                if (!arList.isEmpty()) {
                    doctorName = 'Dr. ' + arList[0].ServiceResource.Name.replace('SR_', '').replace('_', ' ');
                }

                // Get patient name
                Account patient = [SELECT FirstName, LastName FROM Account WHERE Id = :appt.ParentRecordId LIMIT 1];

                String facilityName = appt.ServiceTerritory != null && appt.ServiceTerritory.Description != null
                    ? appt.ServiceTerritory.Description.replace('Scheduling territory for ', '')
                    : (appt.ServiceTerritory != null ? appt.ServiceTerritory.Name : 'Unknown');

                String apptDateTime = appt.SchedStartTime.format('EEEE, MMMM d, yyyy \'at\' h:mm a');

                // Cancel the appointment
                appt.Status = 'Canceled';
                if (String.isNotBlank(req.cancellationReason)) {
                    appt.Description = (appt.Description != null ? appt.Description + '\n' : '')
                        + 'Canceled by patient: ' + req.cancellationReason;
                }
                update appt;

                res.success = true;
                res.confirmationMessage = 'Appointment Canceled Successfully.\n\n'
                    + 'Patient: ' + patient.FirstName + ' ' + patient.LastName + '\n'
                    + 'Doctor: ' + doctorName + '\n'
                    + 'Type: ' + appt.WorkType.Name + '\n'
                    + 'Was Scheduled: ' + apptDateTime + '\n'
                    + 'Facility: ' + facilityName + '\n'
                    + 'Appointment ID: ' + appt.Id + '\n\n'
                    + 'If you need to rebook, just let me know and I can help you schedule a new appointment.';

            } catch (Exception e) {
                res.success = false;
                res.confirmationMessage = 'Cancellation failed: ' + e.getMessage()
                    + '. Please try again or contact 1800-ONCO-HELP.';
            }

            responses.add(res);
        }
        return responses;
    }
}