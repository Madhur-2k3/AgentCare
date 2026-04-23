public without sharing class OncoGetFacilitiesByCity {

    public class FacilityRequest {
        @InvocableVariable(required=true description='City name — Hyderabad, Bengaluru, Chennai, Mumbai, or New Delhi')
        public String city;
    }

    public class FacilityResponse {
        @InvocableVariable(description='Formatted list of facilities in the city')
        public String facilitiesList;
        @InvocableVariable(description='Number of facilities found')
        public Integer totalFacilities;
    }

    public class FacilityOutput {
        @InvocableVariable public FacilityResponse facilityResponse;
    }
        

    @InvocableMethod(label='Get Facilities By City' description='Find Onco Global facilities/territories in a given city')
    public static List<FacilityOutput> getFacilities(List<FacilityRequest> requests) {
        List<FacilityOutput> responses = new List<FacilityOutput>();

        for (FacilityRequest req : requests) {
            FacilityOutput res = new FacilityOutput();

            List<ServiceTerritory> territories = [
                SELECT Id, Name, Street, City, State, PostalCode, Description,
                       OperatingHours.Name, OperatingHours.Description
                FROM ServiceTerritory
                WHERE City = :req.city
                AND IsActive = true
                ORDER BY Name
            ];

            String formatted = '';
            Integer count = 0;
            for (ServiceTerritory st : territories) {
                count++;
                // Extract friendly name from Description (e.g., "Scheduling territory for Onco Global Banjara Hills Cancer Center")
                String facilityName = st.Description != null
                    ? st.Description.replace('Scheduling territory for ', '')
                    : st.Name;
                formatted += count + '. ' + facilityName;
                formatted += '\n   Address: ' + st.Street + ', ' + st.City + ' - ' + st.PostalCode;
                formatted += '\n   Hours: ' + (st.OperatingHours != null ? st.OperatingHours.Description : 'Standard hours');
                formatted += '\n   Territory ID: ' + st.Id;
                formatted += '\n';
            }

            res.facilityResponse.facilitiesList = formatted;
            res.facilityResponse.totalFacilities = count;
            responses.add(res);
        }
        return responses;
    }
}
