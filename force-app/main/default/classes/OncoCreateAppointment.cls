public without sharing class OncoCreateAppointment {

    public class BookingRequest {
        @InvocableVariable(required=true description='Patient Person Account Id')
        public String patientAccountId;
        @InvocableVariable(required=true description='ServiceTerritory Id of the facility')
        public String serviceTerritoryId;
        @InvocableVariable(required=true description='Doctor service resource name e.g. SR_Ananya_Rao')
        public String serviceResourceName;
        @InvocableVariable(required=true description='WorkType name e.g. Follow-Up Review')
        public String workTypeName;
        @InvocableVariable(required=true description='Confirmed start date and time')
        public DateTime scheduledStartTime;
    }

    public class BookingResponse {
        @InvocableVariable(description='Whether booking was successful')
        public Boolean success;
        @InvocableVariable(description='Appointment Id')
        public String appointmentId;
        @InvocableVariable(description='Booking confirmation message')
        public String confirmationMessage;
    }

    @InvocableMethod(label='Create Appointment' description='Book a new appointment by creating ServiceAppointment and AssignedResource')
    public static List<BookingResponse> createAppointment(List<BookingRequest> requests) {
        List<BookingResponse> responses = new List<BookingResponse>();

        for (BookingRequest req : requests) {
            BookingResponse res = new BookingResponse();

            try {
                // Get WorkType directly
                WorkType wt = [
                    SELECT Id, Name, EstimatedDuration, Description
                    FROM WorkType
                    WHERE Name = :req.workTypeName LIMIT 1
                ];

                Integer duration = (Integer) wt.EstimatedDuration;
                DateTime endTime = req.scheduledStartTime.addMinutes(duration);

                ServiceResource sr = [
                    SELECT Id, Name, RelatedRecordId FROM ServiceResource
                    WHERE Name = :req.serviceResourceName LIMIT 1
                ];

                ServiceTerritory st = [
                    SELECT Id, Name, Street, City, State, PostalCode, Country, Description
                    FROM ServiceTerritory WHERE Id = :req.serviceTerritoryId LIMIT 1
                ];

                String doctorName = 'Dr. ' + req.serviceResourceName.replace('SR_', '').replace('_', ' ');
                Account patient = [SELECT FirstName, LastName FROM Account WHERE Id = :req.patientAccountId LIMIT 1];
                String patientName = patient.FirstName + ' ' + patient.LastName;

                String facilityName = st.Description != null
                    ? st.Description.replace('Scheduling territory for ', '')
                    : st.Name;

                ServiceAppointment appt = new ServiceAppointment(
                    ParentRecordId = req.patientAccountId,
                    // AccountId = req.patientAccountId,         // Patient (Person Account)
                    ContactId = sr.RelatedRecordId,            // Doctor (Contact record linked to ServiceResource)
                    Subject = wt.Name + ' - ' + patientName + ' with ' + doctorName,
                    ServiceTerritoryId = req.serviceTerritoryId,
                    WorkTypeId = wt.Id,
                    SchedStartTime = req.scheduledStartTime,
                    SchedEndTime = endTime,
                    Status = 'Scheduled',
                    Description = 'Booked via Onco Global Digital Assistant. ' + wt.Description,
                    Street = st.Street,
                    City = st.City,
                    State = st.State,
                    PostalCode = st.PostalCode,
                    Country = st.Country
                );
                insert appt;

                AssignedResource assignedRes = new AssignedResource(
                    ServiceAppointmentId = appt.Id,
                    ServiceResourceId = sr.Id
                );
                insert assignedRes;

                res.success = true;
                res.appointmentId = appt.Id;
                res.confirmationMessage = 'Appointment Booked Successfully!\n\n'
                    + 'Patient: ' + patientName + '\n'
                    + 'Doctor: ' + doctorName + '\n'
                    + 'Type: ' + wt.Name + '\n'
                    + 'Facility: ' + facilityName + '\n'
                    + 'Address: ' + st.Street + ', ' + st.City + ' - ' + st.PostalCode + '\n'
                    + 'Date & Time: ' + req.scheduledStartTime.format('EEEE, MMMM d, yyyy \'at\' h:mm a') + '\n'
                    + 'Duration: ' + duration + ' minutes\n'
                    + 'Appointment ID: ' + appt.Id + '\n\n'
                    + 'Preparation: ' + wt.Description + '\n\n'
                    + 'Please arrive 15 minutes before your scheduled time.';

            } catch (Exception e) {
                res.success = false;
                res.confirmationMessage = 'Booking failed: ' + e.getMessage()
                    + '. Please try again or contact 1800-ONCO-HELP.';
            }

            responses.add(res);
        }
        return responses;
    }
}
