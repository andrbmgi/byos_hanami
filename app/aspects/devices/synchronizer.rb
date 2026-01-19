# frozen_string_literal: true

require "dry/monads"
require "pipeable"

module Terminus
  module Aspects
    module Devices
      # Updates device based on firmware header information.
      class Synchronizer
        include Deps[
          :settings,
          :logger,
          firmware_parser: "aspects.firmware.header",
          repository: "repositories.device"
        ]
        include Pipeable
        include Dry::Monads[:result]

        def call(headers)
          logger.info "Synchronizer called with headers",
                     http_id: headers["HTTP_ID"],
                     http_fw_version: headers["HTTP_FW_VERSION"],
                     http_model: headers["HTTP_MODEL"]
          
          result = firmware_parser.call(headers)
          
          case result
            in Success(payload)
              logger.info "Firmware parser succeeded", mac_address: payload.mac_address
              update(result)
            in Failure(message)
              logger.error "Firmware parser failed", error: message, headers: headers.slice("HTTP_ID", "HTTP_FW_VERSION", "HTTP_MODEL")
              result
          end
        end

        private

        def update result
          result.bind do |payload|
            logger.info "Looking up device by MAC address",
                       mac_address: payload.mac_address,
                       device_attributes: payload.device_attributes
            
            device = repository.update_by_mac_address payload.mac_address,
                                                      **payload.device_attributes
            
            if device
              logger.info "Device found and updated",
                         device_id: device.id,
                         device_name: device.name,
                         mac_address: device.mac_address
              Success(device)
            else
              logger.error "Device not found in database",
                          mac_address: payload.mac_address
              Failure("Unable to find device by MAC address.")
            end
          end
        end
      end
    end
  end
end
