import os
import sys
import json
import datetime
import requests

# Load config data from config.json
try:
    with open('config.json') as config_file:
        config = json.load(config_file)
except FileNotFoundError as err:
    print("Error: %s: '%s'. Exiting." % (err.strerror, err.filename))
    exit()
except json.JSONDecodeError as err:
    print("Error: 'config.json' is empty or invalid. Exiting.")
    exit()

# Fetch config variables if config.json loads sucessfully
try:
    device42_config = config['device42']
    other_config = config['other']

    d42_host = device42_config['host']
    d42_verify = device42_config['verify']
    d42_username = device42_config['username']
    d42_password = device42_config['password']
    output_path = other_config['output_path']
    debug_level = other_config['debug_level']
except KeyError as err:
    print("Error: %s key not found in 'config.json'. Exiting." % (err))
    exit()

# Check to see if output_path is a directory
if(os.path.isdir(output_path)):
    pass
else:
    print("Error: Output Path: '%s' is not a directory. Exiting." % (output_path))
    exit()

# Check to see if there is a DOQL file path specified
try:
    doql_file_path = sys.argv[1]
except IndexError as err:
    print("Error: No SQL file path specified. Exiting.")
    exit()

# If a file path was specified, validate that the path exists and is a file of type '.sql'
if(os.path.exists(doql_file_path)):
    if(os.path.isfile(doql_file_path)):
        file_ext = doql_file_path[-4:]
        if(file_ext != '.sql'):
            print("Error: '%s' is not of type '.sql'. Exiting." %
                  (doql_file_path))
            exit()
    else:
        print("Error: '%s' is not a file. Exiting." % (doql_file_path))
        exit()
else:
    print("Error: '%s': Path does not exist. Exiting." % (doql_file_path))
    exit()

# Grab the name of the file (We use this as the prefix of the results file)
doql_path_basename = os.path.basename(doql_file_path)

# Load the query from the .sql file specified
doql_query = None
with open(doql_file_path) as doql_file:
    doql_query = doql_file.read()

# Send the query through a POST request to the instance specified and save the output
if(doql_query is not None):
    d42_doql_endpoint = '/services/data/v1.0/query/'
    url = d42_host + d42_doql_endpoint
    data = {
        "query": doql_query,
        "output_type": 'csv',
        "header": "yes"
    }
    if(debug_level == 'verbose'):
        print("Query loaded from: '%s'. Sending request to: '%s'." %
              (doql_file_path, url))

    r = requests.post(url=url, data=data,
                      auth=(d42_username, d42_password), verify=d42_verify)

    if(r.status_code != 200):
        print("%s\n%s" % (r, r.content))
    else:
        csv_data = r.content

        csv_file_path = output_path + doql_path_basename[:-4] + \
            "-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S") + '.csv'

        with open(csv_file_path, "wb") as csv_file:
            csv_file.write(csv_data)
