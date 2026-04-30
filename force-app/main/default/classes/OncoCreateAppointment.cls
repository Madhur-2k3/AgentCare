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

    public class BookingOutput {
        @InvocableVariable public BookingResponse bookingResponse;
    }

    @InvocableMethod(label='Create Appointment' description='Book a new appointment by creating ServiceAppointment and AssignedResource')
    public static List<BookingOutput> createAppointment(List<BookingRequest> requests) {
        List<BookingOutput> responses = new List<BookingOutput>();

        for (BookingRequest req : requests) {
            BookingOutput out = new BookingOutput();
            out.bookingResponse = new BookingResponse();

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

                // ── Double-check for slot conflicts before booking ──
                List<ServiceAppointment> conflicting = [
                    SELECT Id FROM ServiceAppointment
                    WHERE Id IN (SELECT ServiceAppointmentId FROM AssignedResource
                                 WHERE ServiceResourceId = :sr.Id)
                    AND SchedStartTime < :endTime
                    AND SchedEndTime   > :req.scheduledStartTime
                    AND Status != 'Canceled'
                    LIMIT 1
                ];
                if (!conflicting.isEmpty()) {
                    out.bookingResponse.success = false;
                    out.bookingResponse.confirmationMessage =
                        'This time slot has already been booked. Please go back and choose a different slot.';
                    responses.add(out);
                    continue;
                }

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

                // Resolve the doctor's Contact record.
                // ServiceResource.RelatedRecordId is a User (005) without a linked Contact,
                // so we derive the name from serviceResourceName (e.g. SR_Ananya_Rao)
                // and look up the doctor Contact directly by name.
                Id doctorContactId = null;

                // SR_Ananya_Rao → ['Ananya', 'Rao']
                String cleanName = req.serviceResourceName.replace('SR_', '');
                List<String> nameParts = cleanName.split('_');
                if (nameParts.size() >= 2) {
                    String firstName = nameParts[0];
                    String lastName = nameParts[nameParts.size() - 1];
                    List<Contact> doctorContacts = [
                        SELECT Id FROM Contact
                        WHERE FirstName = :firstName AND LastName = :lastName
                        LIMIT 1
                    ];
                    if (!doctorContacts.isEmpty()) {
                        doctorContactId = doctorContacts[0].Id;
                    }
                }

                ServiceAppointment appt = new ServiceAppointment(
                    ParentRecordId = req.patientAccountId,
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

                // Only set ContactId if we resolved a valid Contact
                if (doctorContactId != null) {
                    appt.ContactId = doctorContactId;
                }
                insert appt;

                // Populate the booking receipt URL on the appointment
                // Use Site.getBaseUrl() for Experience Cloud, fallback to org URL
                String baseUrl = Site.getBaseUrl();
                if (String.isBlank(baseUrl)) {
                    baseUrl = URL.getOrgDomainURL().toExternalForm();
                }
                appt.ApptBookingInfoUrl = baseUrl + '/apex/OncoBookingReceipt?id=' + appt.Id;
                update appt;

                AssignedResource assignedRes = new AssignedResource(
                    ServiceAppointmentId = appt.Id,
                    ServiceResourceId = sr.Id
                );
                insert assignedRes;

                out.bookingResponse.success = true;
                out.bookingResponse.appointmentId = appt.Id;
                out.bookingResponse.confirmationMessage = 'Appointment Booked Successfully!\n\n'
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
                out.bookingResponse.success = false;
                out.bookingResponse.confirmationMessage = 'Booking failed: ' + e.getMessage()
                    + '. Please try again or contact 1800-ONCO-HELP.';
            }

            responses.add(out);
        }
        return responses;
    }
}

