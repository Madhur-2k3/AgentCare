public without sharing class OncoGetPatientAppointments {

    public class AppointmentRequest {
        @InvocableVariable(required=true description='Patient registered email address used during identification')
        public String patientEmail;
        @InvocableVariable(description='Filter by status: Scheduled, Completed, Canceled, or All. Default is Scheduled.')
        public String statusFilter;
    }

    public class AppointmentResponse {
        @InvocableVariable(description='Formatted list of patient appointments')
        public String appointmentsList;
        @InvocableVariable(description='Number of appointments found')
        public Integer totalAppointments;
        @InvocableVariable(description='Patient Account Id resolved from email')
        public String patientAccountId;
    }

    public class AppointmentOutput {
        @InvocableVariable public AppointmentResponse appointmentResponse;
    }

    @InvocableMethod(label='Get Patient Appointments' description='Retrieve upcoming or past appointments for a patient using their email')
    public static List<AppointmentOutput> getAppointments(List<AppointmentRequest> requests) {
        List<AppointmentOutput> responses = new List<AppointmentOutput>();

        for (AppointmentRequest req : requests) {
            AppointmentOutput out = new AppointmentOutput();
            out.appointmentResponse = new AppointmentResponse();

            // Look up Account by email internally — avoids LLM ID hallucination
            List<Account> patients = [
                SELECT Id FROM Account
                WHERE IsPersonAccount = true
                AND PersonEmail = :req.patientEmail
                LIMIT 1
            ];

            if (patients.isEmpty()) {
                out.appointmentResponse.appointmentsList = 'No patient found with this email.';
                out.appointmentResponse.totalAppointments = 0;
                responses.add(out);
                continue;
            }

            Id accountId = patients[0].Id;
            out.appointmentResponse.patientAccountId = accountId;

            // Default to Scheduled if no filter provided
            String statusVal = String.isNotBlank(req.statusFilter) ? req.statusFilter : 'Scheduled';

            List<ServiceAppointment> appointments;

            if (statusVal == 'All') {
                appointments = [
                    SELECT Id, Subject, Status, SchedStartTime, SchedEndTime,
                           WorkType.Name, WorkType.EstimatedDuration,
                           ServiceTerritory.Name, ServiceTerritory.Description,
                           ServiceTerritory.Street, ServiceTerritory.City, ServiceTerritory.PostalCode,
                           Description
                    FROM ServiceAppointment
                    WHERE ParentRecordId = :accountId
                    ORDER BY SchedStartTime DESC
                    LIMIT 20
                ];
            } else {
                appointments = [
                    SELECT Id, Subject, Status, SchedStartTime, SchedEndTime,
                           WorkType.Name, WorkType.EstimatedDuration,
                           ServiceTerritory.Name, ServiceTerritory.Description,
                           ServiceTerritory.Street, ServiceTerritory.City, ServiceTerritory.PostalCode,
                           Description
                    FROM ServiceAppointment
                    WHERE ParentRecordId = :accountId
                    AND Status = :statusVal
                    ORDER BY SchedStartTime ASC
                    LIMIT 20
                ];
            }

            if (appointments.isEmpty()) {
                out.appointmentResponse.appointmentsList = 'No ' + statusVal.toLowerCase() + ' appointments found.';
                out.appointmentResponse.totalAppointments = 0;
                responses.add(out);
                continue;
            }

            // Get assigned doctor names for these appointments
            Set<Id> apptIds = new Set<Id>();
            for (ServiceAppointment sa : appointments) {
                apptIds.add(sa.Id);
            }

            Map<Id, String> apptToDoctorMap = new Map<Id, String>();
            for (AssignedResource ar : [
                SELECT ServiceAppointmentId, ServiceResource.Name
                FROM AssignedResource
                WHERE ServiceAppointmentId IN :apptIds
            ]) {
                String doctorName = 'Dr. ' + ar.ServiceResource.Name.replace('SR_', '').replace('_', ' ');
                apptToDoctorMap.put(ar.ServiceAppointmentId, doctorName);
            }

            // Build formatted output
            String formatted = '';
            Integer count = 0;
            for (ServiceAppointment sa : appointments) {
                count++;
                String facilityName = sa.ServiceTerritory != null && sa.ServiceTerritory.Description != null
                    ? sa.ServiceTerritory.Description.replace('Scheduling territory for ', '')
                    : (sa.ServiceTerritory != null ? sa.ServiceTerritory.Name : 'Unknown');

                String doctorName = apptToDoctorMap.containsKey(sa.Id)
                    ? apptToDoctorMap.get(sa.Id)
                    : 'Unassigned';

                formatted += count + '. ' + sa.WorkType.Name + ' with ' + doctorName;
                formatted += '\n   Status: ' + sa.Status;
                formatted += '\n   Date: ' + sa.SchedStartTime.format('EEEE, MMMM d, yyyy');
                formatted += '\n   Time: ' + sa.SchedStartTime.format('h:mm a') + ' to ' + sa.SchedEndTime.format('h:mm a');
                formatted += '\n   Facility: ' + facilityName;
                if (sa.ServiceTerritory != null) {
                    formatted += '\n   Address: ' + sa.ServiceTerritory.Street + ', ' + sa.ServiceTerritory.City + ' - ' + sa.ServiceTerritory.PostalCode;
                }
                formatted += '\n   Appointment ID: ' + sa.Id;
                formatted += '\n';
            }

            out.appointmentResponse.appointmentsList = formatted;
            out.appointmentResponse.totalAppointments = count;
            responses.add(out);
        }
        return responses;
    }
}