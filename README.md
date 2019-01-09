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

This API will fetch the event information stored in known s3 locations. This information will be used by the mapping UI interface https://github.com/zooniverse/prn-maps for visualizing the results of tPRN event

# Routes

`/events`
  + List all known tPRN event manifests available in s3

`/events/${event_name}`
  + Show the JSON manifest metadata for the known event

# Get started

`bundle exec puma` to run the API server in development mode
