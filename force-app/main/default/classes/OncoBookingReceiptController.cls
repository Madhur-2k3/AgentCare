public without sharing class OncoBookingReceiptController {

    private ServiceAppointment appt;
    private Account patient;
    private String resolvedDoctorName;
    private WorkType wt;

    public OncoBookingReceiptController() {
        String apptId = ApexPages.currentPage().getParameters().get('id');
        if (String.isNotBlank(apptId)) {
            loadAppointment(apptId);
        }
    }

    private void loadAppointment(String apptId) {
        List<ServiceAppointment> appts = [
            SELECT Id, AppointmentNumber, Subject, Status,
                   SchedStartTime, SchedEndTime,
                   WorkTypeId, WorkType.Name, WorkType.EstimatedDuration, WorkType.Description,
                   ParentRecordId,
                   ServiceTerritoryId, ServiceTerritory.Name, ServiceTerritory.Description,
                   Street, City, State, PostalCode, Country,
                   Description
            FROM ServiceAppointment
            WHERE Id = :apptId
            LIMIT 1
        ];

        if (appts.isEmpty()) return;
        appt = appts[0];

        // Load patient (Person Account)
        if (appt.ParentRecordId != null) {
            List<Account> patients = [
                SELECT FirstName, LastName
                FROM Account
                WHERE Id = :appt.ParentRecordId
                LIMIT 1
            ];
            if (!patients.isEmpty()) {
                patient = patients[0];
            }
        }

        // Resolve doctor name from AssignedResource
        List<AssignedResource> ars = [
            SELECT ServiceResource.Name
            FROM AssignedResource
            WHERE ServiceAppointmentId = :appt.Id
            LIMIT 1
        ];
        if (!ars.isEmpty()) {
            // Convert SR_Ananya_Rao → Dr. Ananya Rao
            String srName = ars[0].ServiceResource.Name;
            resolvedDoctorName = 'Dr. ' + srName.replace('SR_', '').replace('_', ' ');
        }
    }

    // ─── Getter Properties for VF Page ───

    public Boolean getHasAppointment() {
        return appt != null;
    }

    public String getAppointmentNumber() {
        return appt != null ? appt.AppointmentNumber : '';
    }

    public String getAppointmentId() {
        return appt != null ? appt.Id : '';
    }

    public String getPatientName() {
        if (patient == null) return '';
        return (patient.FirstName != null ? patient.FirstName : '') + ' '
             + (patient.LastName != null ? patient.LastName : '');
    }

    public String getDoctorName() {
        return resolvedDoctorName != null ? resolvedDoctorName : '';
    }

    public String getAppointmentType() {
        return (appt != null && appt.WorkType != null) ? appt.WorkType.Name : '';
    }

    public String getFacilityName() {
        if (appt == null || appt.ServiceTerritory == null) return '';
        String territoryDescription = appt.ServiceTerritory.Description;
        if (territoryDescription != null && territoryDescription.length() > 0) {
            return territoryDescription.replace('Scheduling territory for ', '');
        }
        return appt.ServiceTerritory.Name;
    }

    public String getAddress() {
        if (appt == null) return '';
        List<String> parts = new List<String>();
        if (appt.Street != null && appt.Street.length() > 0) parts.add(appt.Street);
        if (appt.City != null && appt.City.length() > 0) parts.add(appt.City);
        if (appt.State != null && appt.State.length() > 0) parts.add(appt.State);
        if (appt.PostalCode != null && appt.PostalCode.length() > 0) parts.add(appt.PostalCode);
        return String.join(parts, ', ');
    }

    public String getFormattedDateTime() {
        if (appt == null || appt.SchedStartTime == null) return '';
        return appt.SchedStartTime.format('EEEE, MMMM d, yyyy \'at\' h:mm a');
    }

    public String getDuration() {
        if (appt == null || appt.WorkType == null || appt.WorkType.EstimatedDuration == null) return '';
        return String.valueOf(appt.WorkType.EstimatedDuration.intValue()) + ' minutes';
    }

    public String getPreparation() {
        if (appt == null || appt.WorkType == null) return '';
        return appt.WorkType.Description;
    }

    public Boolean getHasPreparation() {
        String prep = getPreparation();
        return prep != null && prep.length() > 0;
    }

    public String getStatus() {
        return appt != null ? appt.Status : '';
    }

    public String getGeneratedDate() {
        return DateTime.now().format('MMMM d, yyyy \'at\' h:mm a');
    }
}