# frozen_string_literal: true

module Terminus
  module Actions
    module API
      module Screens
        # The patch action.
        # :reek:DataClump
        class Patch < Base
          include Deps[
            :mini_magick,
            "aspects.screens.creators.temp_path",
            repository: "repositories.screen",
            model_repository: "repositories.model"
          ]
          include Initable[mold: Aspects::Screens::Mold, serializer: Serializers::Screen]

          using Refines::Actions::Response

          params do
            required(:id).filled(:integer)

            required(:screen).filled(:hash) do
              optional(:model_id).filled :integer
              optional(:label).filled :string
              optional(:name).filled :string
              optional(:content).filled :string
              optional(:uri).filled :string
              optional(:preprocessed).filled :bool
            end
          end

          def handle request, response
            parameters = request.params
            screen = repository.find parameters[:id]

            if parameters.valid? && screen
              render update(screen, parameters[:screen]), response
            else
              unprocessable_content parameters.errors.to_h, response
            end
          end

          private

          def render result, response
            case result
              in Success(update) then response.body = {data: serializer.new(update).to_h}.to_json
              else unprocessable_content_on_failure result, response
            end
          end

          def update screen, parameters
            has_uri = parameters.key?(:uri) && !parameters[:uri].nil? && !parameters[:uri].empty?
            has_preprocessed = parameters.key?(:preprocessed) && parameters[:preprocessed] == true
            
            if parameters.key?(:content)
              merge(screen, parameters).bind { |attributes| build_mold attributes }
                                       .bind { |instance| screenshot instance, screen, parameters }
            elsif has_uri && has_preprocessed
              merge(screen, parameters).bind { |attributes| build_mold_for_preprocessed attributes }
                                       .bind { |instance| replace_preprocessed instance, screen, parameters }
            else
              Success repository.update(screen.id, **parameters.except(:uri, :preprocessed, :content))
            end
          end

          def merge screen, parameters
            Success screen.to_h
                          .slice(:model_id, :label, :name)
                          .merge! parameters.slice(:model_id, :label, :name, :content, :uri)
          end

          def build_mold attributes
            id = attributes[:model_id]

            model_repository.find(id).then do |record|
              if record
                Success mold.for(record, **attributes.slice(:label, :name, :content))
              else
                Failure "Unable to find model for ID: #{id}."
              end
            end
          end

          def build_mold_for_preprocessed attributes
            id = attributes[:model_id]

            model_repository.find(id).then do |record|
              if record
                Success mold.for(record, **attributes.slice(:label, :name).merge(content: attributes[:uri]))
              else
                Failure "Unable to find model for ID: #{id}."
              end
            end
          end

          def screenshot mold, screen, parameters
            temp_path.call(mold) { |path| replace path, screen, **parameters }
          end

          def replace_preprocessed mold, screen, parameters
            Pathname.mktmpdir do |directory|
              path = Pathname(directory).join("input.png")
              
              # Download and write the preprocessed image
              mini_magick::Image.open(mold.content)
                               .write(path)
                               .then do
                # Replace the screen's image with the downloaded one
                path.open { |io| screen.replace io, metadata: {"filename" => mold.filename} }
                Success repository.update(screen.id, 
                                        image_data: screen.image_attributes, 
                                        **parameters.except(:uri, :preprocessed))
              end
            end
          rescue => error
            Failure "Failed to process preprocessed image: #{error.message}"
          end

          def replace(path, screen, **)
            path.open { |io| screen.replace io, metadata: {"filename" => path.basename} }
            Success repository.update(screen.id, image_data: screen.image_attributes, **)
          end

          def unprocessable_content errors, response
            body = problem[
              type: "/problem_details#screen_payload",
              status: :unprocessable_content,
              detail: "Validation failed.",
              instance: "/api/screens",
              extensions: {errors:}
            ]

            response.with body: body.to_json, format: :problem_details, status: 422
          end

          def unprocessable_content_on_failure result, response
            body = problem[
              type: "/problem_details#screen_payload",
              status: :unprocessable_content,
              detail: result.failure,
              instance: "/api/screens"
            ]

            response.with body: body.to_json, format: :problem_details, status: 422
          end
        end
      end
    end
  end
end
