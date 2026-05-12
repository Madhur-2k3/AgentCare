public without sharing class OncoRescheduleAppointment {

    public class RescheduleRequest {
        @InvocableVariable(required=true description='The ServiceAppointment Id to reschedule')
        public String appointmentId;
        @InvocableVariable(required=true description='New start date and time for the appointment')
        public DateTime newStartTime;
    }

    public class RescheduleResponse {
        @InvocableVariable(description='Whether reschedule was successful')
        public Boolean success;
        @InvocableVariable(description='Reschedule confirmation message')
        public String confirmationMessage;
    }

    @InvocableMethod(label='Reschedule Appointment' description='Update an existing appointment with a new date and time')
    public static List<RescheduleResponse> rescheduleAppointment(List<RescheduleRequest> requests) {
        List<RescheduleResponse> responses = new List<RescheduleResponse>();

        for (RescheduleRequest req : requests) {
            RescheduleResponse res = new RescheduleResponse();

            try {
                // Get the existing appointment with all details
                ServiceAppointment appt = [
                    SELECT Id, Subject, Status, SchedStartTime, SchedEndTime,
                           WorkType.Name, WorkType.EstimatedDuration,
                           ServiceTerritory.Name, ServiceTerritory.Description,
                           ServiceTerritory.Street, ServiceTerritory.City, ServiceTerritory.PostalCode,
                           ParentRecordId
                    FROM ServiceAppointment
                    WHERE Id = :req.appointmentId
                    LIMIT 1
                ];

                // Validate: Only scheduled appointments can be rescheduled
                if (appt.Status != 'Scheduled') {
                    res.success = false;
                    res.confirmationMessage = 'This appointment cannot be rescheduled because its status is "' 
                        + appt.Status + '". Only scheduled appointments can be rescheduled.';
                    responses.add(res);
                    continue;
                }

                // Validate: New time must be in the future (at least 24 hours)
                if (req.newStartTime < DateTime.now().addHours(24)) {
                    res.success = false;
                    res.confirmationMessage = 'The new appointment time must be at least 24 hours from now.';
                    responses.add(res);
                    continue;
                }

                // Store old time for confirmation message
                String oldDateTime = appt.SchedStartTime.format('EEEE, MMMM d, yyyy \'at\' h:mm a');

                // Calculate new end time based on work type duration
                Integer duration = (Integer) appt.WorkType.EstimatedDuration;
                DateTime newEndTime = req.newStartTime.addMinutes(duration);

                // Update the appointment
                appt.SchedStartTime = req.newStartTime;
                appt.SchedEndTime = newEndTime;
                update appt;

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

                String facilityName = appt.ServiceTerritory.Description != null
                    ? appt.ServiceTerritory.Description.replace('Scheduling territory for ', '')
                    : appt.ServiceTerritory.Name;

                String newDateTime = req.newStartTime.format('EEEE, MMMM d, yyyy \'at\' h:mm a');

                res.success = true;
                res.confirmationMessage = 'Appointment Rescheduled Successfully!\n\n'
                    + 'Patient: ' + patient.FirstName + ' ' + patient.LastName + '\n'
                    + 'Doctor: ' + doctorName + '\n'
                    + 'Type: ' + appt.WorkType.Name + '\n'
                    + 'Facility: ' + facilityName + '\n\n'
                    + 'Previous: ' + oldDateTime + '\n'
                    + 'New: ' + newDateTime + '\n'
                    + 'Duration: ' + duration + ' minutes\n\n'
                    + 'Appointment ID: ' + appt.Id + '\n'
                    + 'Please arrive 15 minutes before your new scheduled time.';

            } catch (Exception e) {
                res.success = false;
                res.confirmationMessage = 'Reschedule failed: ' + e.getMessage()
                    + '. Please try again or contact 1800-ONCO-HELP.';
            }

            responses.add(res);
        }
        return responses;
    }
}