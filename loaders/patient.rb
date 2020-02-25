# frozen_string_literal: true

require_relative 'person'

module Loaders
  module Patient
    def self.load(patient)
      LOGGER.debug("Saving patient: #{JSON.dump(patient)}")
      person_id = Person.load(patient[:person])
      patient_id = load_patient(person_id)
      load_patient_identifiers(patient_id, patient[:identifiers])
      load_encounters(patient_id, patient[:encounters])
      patient_id
    end

    def self.load_patient(person_id)
      LOGGER.debug("Saving patient ##{person_id}")
      NartDb.into_table[:patient]
            .insert(patient_id: person_id,
                    creator: EMR_USER_ID,
                    date_created: DateTime.now)
    end

    def self.load_patient_identifiers(patient_id, identifiers)
      LOGGER.debug("Saving patient ##{patient_id} identifiers")
      identifiers.each do |identifier|
        NartDb.into_table[:patient_identifier]
              .insert(patient_id: patient_id,
                      creator: EMR_USER_ID,
                      date_created: DateTime.now,
                      location_id: EMR_USER_ID,
                      uuid: SecureRandom.uuid,
                      **identifier)
      end
    end

    def self.load_encounters(patient_id, encounters)
      LOGGER.debug("Saving patient ##{patient_id} encounters")
      encounters.each do |encounter|
        LOGGER.debug("Saving patient ##{patient_id} encounter: #{encounter[:encounter_datetime]} - #{encounter[:encounter_type_id]}")
        byebug unless encounter[:encounter_type_id]
        encounter_id = NartDb.into_table[:encounter]
                             .insert(encounter_type: encounter[:encounter_type_id],
                                     patient_id: patient_id,
                                     program_id: Nart::Programs::HIV_PROGRAM,
                                     encounter_datetime: encounter[:encounter_datetime],
                                     date_created: DateTime.now,
                                     creator: EMR_USER_ID,
                                     provider_id: EMR_USER_ID,
                                     location_id: EMR_LOCATION_ID,
                                     uuid: SecureRandom.uuid)

        load_observations(patient_id, encounter_id, encounter[:observations])
      end
    end

    def self.load_observations(patient_id, encounter_id, observations)
      LOGGER.debug("Saving observations for encounter ##{encounter_id}")
      LOGGER.debug(observations)
      observations&.each do |observation|
        LOGGER.debug("Saving encounter ##{encounter_id} observation: #{observation[:obs_datetime]} - #{observation[:concept_id]}")
        observation = observation.dup
        children = observation.delete(:children)

        observation_id = NartDb.into_table[:obs]
                               .insert(uuid: SecureRandom.uuid,
                                       creator: EMR_USER_ID,
                                       date_created: DateTime.now,
                                       location_id: EMR_LOCATION_ID,
                                       encounter_id: encounter_id,
                                       person_id: patient_id,
                                       comments: 'Migrated from eMastercard',
                                       **observation)

        next unless children

        LOGGER.debug("Saving observation ##{observation} children")
        load_observations(patient_id,
                          encounter_id,
                          children.map { |child| { obs_group_id: observation_id, **child } })
      end
    end
  end
end
