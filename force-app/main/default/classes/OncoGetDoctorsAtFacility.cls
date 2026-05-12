public without sharing class OncoGetDoctorsAtFacility {

    public class DoctorRequest {
        @InvocableVariable(required=true description='ServiceTerritory Id of the selected facility')
        public String serviceTerritoryId;
        @InvocableVariable(description='WorkType name to filter doctors by matching specialty (e.g. Follow-Up Review, Surgical Consultation)')
        public String workTypeName;
    }

    public class DoctorResponse {
        @InvocableVariable(description='Formatted list of available doctors')
        public String doctorsList;
        @InvocableVariable(description='Number of doctors found')
        public Integer totalDoctors;
    }

    public class DoctorOutput {
        @InvocableVariable public DoctorResponse doctorResponse;
    }

    @InvocableMethod(label='Get Doctors At Facility' description='Find doctors at a facility, optionally filtered by specialty from WorkType')
    public static List<DoctorOutput> getDoctors(List<DoctorRequest> requests) {
        List<DoctorOutput> responses = new List<DoctorOutput>();

        for (DoctorRequest req : requests) {
            DoctorOutput out = new DoctorOutput();
            out.doctorResponse = new DoctorResponse();

            // Step 1: Get ServiceResource IDs assigned to this territory
            List<ServiceTerritoryMember> members = [
                SELECT ServiceResourceId, ServiceResource.Name,
                       OperatingHoursId, OperatingHours.Description
                FROM ServiceTerritoryMember
                WHERE ServiceTerritoryId = :req.serviceTerritoryId
                AND ServiceResource.IsActive = true
            ];

            if (members.isEmpty()) {
                out.doctorResponse.doctorsList = 'No doctors are currently assigned to this facility.';
                out.doctorResponse.totalDoctors = 0;
                responses.add(out);
                continue;
            }

            // Build SR Name → OH Description map
            Map<String, String> srScheduleMap = new Map<String, String>();
            Set<String> srNames = new Set<String>();
            for (ServiceTerritoryMember stm : members) {
                srNames.add(stm.ServiceResource.Name);
                if (stm.OperatingHours != null) {
                    srScheduleMap.put(stm.ServiceResource.Name, stm.OperatingHours.Description);
                }
            }

            // Step 2: Get doctor details from Contact
            Set<String> lastNames = new Set<String>();
            for (String srName : srNames) {
                String cleanName = srName.replace('SR_', '').replace('_', ' ');
                List<String> parts = cleanName.split(' ');
                if (parts.size() > 0) lastNames.add(parts[parts.size() - 1]);
            }

            Map<String, Contact> doctorDetailsMap = new Map<String, Contact>();
            for (Contact c : [
                SELECT Id, FirstName, LastName, Title, Description
                FROM Contact
                WHERE LastName IN :lastNames
                AND Email LIKE '%@oncoglobal.in'
            ]) {
                doctorDetailsMap.put(c.FirstName + ' ' + c.LastName, c);
            }

            // Step 3: If workTypeName provided, find matching specialties
            Set<String> matchingSpecialties = new Set<String>();
            if (String.isNotBlank(req.workTypeName)) {
                List<WorkType> wtList = [
                    SELECT Id FROM WorkType WHERE Name = :req.workTypeName LIMIT 1
                ];
                if (!wtList.isEmpty()) {
                    for (WorkTypeCareSpecialty wtcs : [
                        SELECT CareSpecialty.Name FROM WorkTypeCareSpecialty
                        WHERE WorkTypeId = :wtList[0].Id
                    ]) {
                        matchingSpecialties.add(wtcs.CareSpecialty.Name);
                    }
                }
            }

            // Step 4: Get doctor-specialty mappings
            Map<String, String> doctorSpecialtyMap = new Map<String, String>();
            for (CareProviderFacilitySpecialty cpfs : [
                SELECT PractitionerFacility.Name, Specialty.Name
                FROM CareProviderFacilitySpecialty
                WHERE IsActive = true
            ]) {
                String hpfName = cpfs.PractitionerFacility.Name;
                if (hpfName != null && hpfName.contains(' @ ')) {
                    String docName = hpfName.substringBefore(' @ ').replace('Dr. ', '');
                    doctorSpecialtyMap.put(docName, cpfs.Specialty.Name);
                }
            }

            // Step 5: Build formatted output — try specialty match first, fallback to all
            String formatted = '';
            Integer count = 0;

            // First pass: specialty-matched doctors only
            if (!matchingSpecialties.isEmpty()) {
                for (String srName : srNames) {
                    String cleanName = srName.replace('SR_', '').replace('_', ' ');
                    String specialty = doctorSpecialtyMap.get(cleanName);

                    if (specialty != null && matchingSpecialties.contains(specialty)) {
                        Contact doc = doctorDetailsMap.get(cleanName);
                        count++;
                        formatted += count + '. Dr. ' + cleanName + ' — ' + specialty + ' ✓ (Specialty Match)';
                        if (doc != null && doc.Title != null) formatted += '\n   ' + doc.Title;
                        if (srScheduleMap.containsKey(srName)) {
                            formatted += '\n   Schedule: ' + srScheduleMap.get(srName);
                        }
                        formatted += '\n   Resource: ' + srName;
                        formatted += '\n';
                    }
                }
            }

            // Fallback: if no specialty match, show ALL doctors at this facility
            if (count == 0) {
                if (!matchingSpecialties.isEmpty()) {
                    formatted = 'Note: No ' + String.join(new List<String>(matchingSpecialties), '/') 
                        + ' specialist at this facility. Here are all available doctors:\n\n';
                }
                for (String srName : srNames) {
                    String cleanName = srName.replace('SR_', '').replace('_', ' ');
                    String specialty = doctorSpecialtyMap.get(cleanName);
                    Contact doc = doctorDetailsMap.get(cleanName);
                    count++;
                    formatted += count + '. Dr. ' + cleanName;
                    if (specialty != null) formatted += ' — ' + specialty;
                    if (doc != null && doc.Title != null) formatted += '\n   ' + doc.Title;
                    if (srScheduleMap.containsKey(srName)) {
                        formatted += '\n   Schedule: ' + srScheduleMap.get(srName);
                    }
                    formatted += '\n   Resource: ' + srName;
                    formatted += '\n';
                }
            }

            out.doctorResponse.doctorsList = formatted;
            out.doctorResponse.totalDoctors = count;
            responses.add(out);
        }
        return responses;
    }
}