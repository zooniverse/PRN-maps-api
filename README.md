# PRN-maps-api
API for mapping the Planetary Response Network (tPRN) data results via https://github.com/zooniverse/prn-maps

# Overview
This API is a proxy around s3 files that have been created for each tPRN activation event.

Each Event comprises the following steps:
1. A JSON manifest describing each tPRN event will be created and stored in s3, https://github.com/camallen/PRN-scripts/tree/add_manifest_pipeline/pipeline
0. Before and after imagery of a PRN even is pushed to a Zooniverse project
0. Volunteers classify the uploaded data
0. Raw classification data is collated and archived to a known s3 path
0. IBCC code is run over the collated data and with all the layer results published to known s3 paths

This API will fetch the event information stored in known s3 locations and returned as JSON data.

This information will be used by the mapping UI interface https://github.com/zooniverse/prn-maps for visualizing the results of tPRN event

# Routes

##### Public end points

GET `/events`
  + List all known tPRN event manifests available in s3, including the manifest name and URL for retrieval via HTTPS

GET `/events/${event_name}`
  + Show the event metadata for a known event name

GET `/layers/${event_name}`
  + Show the data layers for a known event name

##### Protected end points (basic auth headers required)

GET `/pending/layers/${event_name}`
  + Show the pending data layers for a known event name

POST `/pending/layers/${event_name}/approve/:${version}`
  + Approve and publish all the pending data layers for a known event name.

POST `/upload/layers/${event_name}`
  + Upload a list of layer files and one metadata files to describe the list of layers. Use `multipart/form-data` encoding to upload the files
      + At least one layer file is expected via `layers[]` param
      + Exactly one metadata JSON file is expected on `metadata` param
  + The metadata JSON file must conform to a valid schema
      ```
      {
      	"layers": [{
      		"file_name": "layer_1.csv",
      		"created_at": "2018-07-07T15:55:00.511Z"
      	},{
      		"file_name": "layer_2.csv",
      		"created_at": "2018-07-07T15:55:00.511Z"
      	}]
      }
      ```

# Get started

Using docker and docker-compose
`docker-compose up`

Using your own ruby install
`bundle install`
`bundle exec puma -C docker/puma.rb` to run the API server in development mode
