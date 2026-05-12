public without sharing class OncoDiscoverProviders {

    public class ProviderRequest {
        @InvocableVariable(description='City to search in — Hyderabad, Bengaluru, Chennai, Mumbai, or New Delhi. Optional.')
        public String city;
        @InvocableVariable(description='Medical specialty to filter by — e.g. Medical Oncology, Surgical Oncology, Radiation Oncology, Hemato-Oncology, Palliative Care, Psycho-Oncology. Optional.')
        public String specialty;
        @InvocableVariable(description='Doctor name to search for (partial match supported). Optional.')
        public String doctorName;
    }

    public class ProviderResponse {
        @InvocableVariable(description='Formatted list of matching providers with facility, specialty, and schedule details')
        public String providersList;
        @InvocableVariable(description='Number of providers found')
        public Integer totalProviders;
        @InvocableVariable(description='Comma-separated list of available specialties at Onco Global')
        public String availableSpecialties;
    }

    // Outer wrapper — wrapper OF the inner wrapper (required for Lightning Types)
    public class ProviderOutput {
        @InvocableVariable public ProviderResponse providerResponse;
    }

    @InvocableMethod(label='Discover Providers' description='Search for doctors by city, specialty, or name across all Onco Global facilities')
    public static List<ProviderOutput> discoverProviders(List<ProviderRequest> requests) {
        List<ProviderOutput> responses = new List<ProviderOutput>();

        for (ProviderRequest req : requests) {
            ProviderOutput res = new ProviderOutput();
            res.providerResponse = new ProviderResponse();

            // Always provide available specialties for context
            List<CareSpecialty> allSpecs = [SELECT Name FROM CareSpecialty ORDER BY Name];
            List<String> specNames = new List<String>();
            for (CareSpecialty cs : allSpecs) {
                specNames.add(cs.Name);
            }
            res.providerResponse.availableSpecialties = String.join(specNames, ', ');

            // Build dynamic query for ServiceTerritoryMember
            String query = 'SELECT ServiceResource.Name, ServiceResource.Id, '
                + 'ServiceTerritory.Name, ServiceTerritory.Id, ServiceTerritory.City, '
                + 'ServiceTerritory.Street, ServiceTerritory.PostalCode, ServiceTerritory.Description, '
                + 'OperatingHours.Description '
                + 'FROM ServiceTerritoryMember '
                + 'WHERE ServiceResource.IsActive = true '
                + 'AND ServiceResource.ResourceType = \'T\'';

            // Filter by city
            if (String.isNotBlank(req.city)) {
                String cleanCity = req.city.replace('_', ' ').trim();
                // Handle common variations
                if (cleanCity.equalsIgnoreCase('Delhi') || cleanCity.equalsIgnoreCase('New Delhi')) {
                    query += ' AND ServiceTerritory.City = \'New Delhi\'';
                } else if (cleanCity.equalsIgnoreCase('Bangalore') || cleanCity.equalsIgnoreCase('Bengaluru')) {
                    query += ' AND ServiceTerritory.City = \'Bengaluru\'';
                } else {
                    query += ' AND ServiceTerritory.City = \'' + String.escapeSingleQuotes(cleanCity) + '\'';
                }
            }

            // Filter by doctor name
            if (String.isNotBlank(req.doctorName)) {
                String cleanName = req.doctorName.replace('Dr.', '').replace('Dr', '').trim();
                String srName = '%' + cleanName.replace(' ', '_') + '%';
                query += ' AND ServiceResource.Name LIKE \'' + String.escapeSingleQuotes(srName) + '\'';
            }

            query += ' ORDER BY ServiceTerritory.City, ServiceResource.Name';

            List<ServiceTerritoryMember> members = Database.query(query);

            if (members.isEmpty()) {
                res.providerResponse.providersList = 'No providers found matching your criteria. Try broadening your search.';
                res.providerResponse.totalProviders = 0;
                responses.add(res);
                continue;
            }

            // Get all resource names for specialty lookup
            Set<String> resourceCleanNames = new Set<String>();
            for (ServiceTerritoryMember stm : members) {
                resourceCleanNames.add(stm.ServiceResource.Name.replace('SR_', '').replace('_', ' '));
            }

            // Get specialties from CareProviderFacilitySpecialty
            Map<String, String> doctorSpecialtyMap = new Map<String, String>();
            for (CareProviderFacilitySpecialty cpfs : [
                SELECT Name FROM CareProviderFacilitySpecialty
            ]) {
                // Parse name format: "Dr. Ananya Rao - Medical Oncology @ Banjara Hills"
                String cpfsName = cpfs.Name;
                if (cpfsName.contains(' - ') && cpfsName.contains(' @ ')) {
                    String docPart = cpfsName.substringAfter('Dr. ').substringBefore(' - ').trim();
                    String specPart = cpfsName.substringAfter(' - ').substringBefore(' @ ').trim();
                    doctorSpecialtyMap.put(docPart, specPart);
                }
            }

            // Get Contact details for titles
            Map<String, Contact> contactMap = new Map<String, Contact>();
            for (Contact c : [
                SELECT FirstName, LastName, Title
                FROM Contact
                WHERE LastName IN :getLastNames(resourceCleanNames)
            ]) {
                contactMap.put(c.FirstName + ' ' + c.LastName, c);
            }

            // Build output — filter by specialty if provided
            String formatted = '';
            Integer count = 0;

            for (ServiceTerritoryMember stm : members) {
                String cleanName = stm.ServiceResource.Name.replace('SR_', '').replace('_', ' ');
                String doctorSpecialty = doctorSpecialtyMap.get(cleanName);

                // Filter by specialty if requested
                if (String.isNotBlank(req.specialty)) {
                    String cleanSpec = req.specialty.replace('_', ' ').trim();
                    if (doctorSpecialty == null || !doctorSpecialty.containsIgnoreCase(cleanSpec)) {
                        continue;
                    }
                }

                String facilityName = stm.ServiceTerritory.Description != null
                    ? stm.ServiceTerritory.Description.replace('Scheduling territory for ', '')
                    : stm.ServiceTerritory.Name;

                Contact doc = contactMap.get(cleanName);

                count++;
                formatted += count + '. Dr. ' + cleanName;
                if (doctorSpecialty != null) formatted += ' — ' + doctorSpecialty;
                formatted += '\n   Facility: ' + facilityName;
                formatted += '\n   City: ' + stm.ServiceTerritory.City;
                if (stm.ServiceTerritory.Street != null) {
                    formatted += '\n   Address: ' + stm.ServiceTerritory.Street + ', ' 
                        + stm.ServiceTerritory.City + ' - ' + stm.ServiceTerritory.PostalCode;
                }
                if (doc != null && doc.Title != null) {
                    formatted += '\n   Title: ' + doc.Title;
                }
                if (stm.OperatingHours != null && stm.OperatingHours.Description != null) {
                    formatted += '\n   Schedule: ' + stm.OperatingHours.Description;
                }
                formatted += '\n   Resource: ' + stm.ServiceResource.Name;
                formatted += '\n   Territory ID: ' + stm.ServiceTerritory.Id;
                formatted += '\n';
            }

            if (count == 0) {
                formatted = 'No providers found for the specialty "' + req.specialty 
                    + '". Available specialties: ' + res.providerResponse.availableSpecialties;
            }

            res.providerResponse.providersList = formatted;
            res.providerResponse.totalProviders = count;
            responses.add(res);
        }
        return responses;
    }

    private static Set<String> getLastNames(Set<String> fullNames) {
        Set<String> lastNames = new Set<String>();
        for (String name : fullNames) {
            List<String> parts = name.split(' ');
            if (parts.size() > 1) {
                lastNames.add(parts[parts.size() - 1]);
            }
        }
        return lastNames;
    }
}