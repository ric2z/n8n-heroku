#!/bin/sh

# check if port variable is set or go with default
if [ -z ${PORT+x} ]; then echo "PORT variable not defined, leaving N8N to default port."; else export N8N_PORT=$PORT; echo "N8N will start on '$PORT'"; fi

# regex function
parse_url() {
  eval $(echo "$1" | sed -e "s#^\(\(.*\)://\)\?\(\([^:@]*\)\(:\(.*\)\)\?@\)\?\([^/?]*\)\(/\(.*\)\)\?#${PREFIX:-URL_}SCHEME='\2' ${PREFIX:-URL_}USER='\4' ${PREFIX:-URL_}PASSWORD='\6' ${PREFIX:-URL_}HOSTPORT='\7' ${PREFIX:-URL_}DATABASE='\9'#")
}

# received url as argument
ARG_URL=${1:-""}

# override if config vars detected
if [ "$DATABASE_URL" ]
then 
    ARG_URL=$DATABASE_URL
	echo "postgres config detected"

elif [ "$MONGODB_URI" ]
then 
    ARG_URL=$MONGODB_URI
	echo "mongo config detected"

else
    echo "no config vars found"
fi

# disable diagnostics
export N8N_DIAGNOSTICS_ENABLED=false

# prefix variables to avoid conflicts and run parse url function on arg url
PREFIX="N8N_DB_" parse_url "$ARG_URL"

# Separate host and port    
N8N_DB_HOST="$(echo $N8N_DB_HOSTPORT | sed -e 's,:.*,,g')"

N8N_DB_PORT="$(echo $N8N_DB_HOSTPORT | sed -e 's,^.*:,:,g' -e 's,.*:\([0-9]*\).*,\1,g' -e 's,[^0-9],,g')"

# DB switch
if [ $N8N_DB_SCHEME == 'postgres' ]
then
    echo "identified DB in use postgreSQL"
	export DB_TYPE=postgresdb
	export DB_POSTGRESDB_HOST=$N8N_DB_HOST
	export DB_POSTGRESDB_PORT=$N8N_DB_PORT
	export DB_POSTGRESDB_DATABASE=$N8N_DB_DATABASE
	export DB_POSTGRESDB_USER=$N8N_DB_USER
	export DB_POSTGRESDB_PASSWORD=$N8N_DB_PASSWORD

elif [ $N8N_DB_SCHEME == 'mongodb' ]
then
    echo "identified DB in use mongoDB"
	export DB_TYPE=mongodb
	export DB_MONGODB_CONNECTION_URL=$ARG_URL
	
else
	echo "invalid url arg"
fi

# parse REDIS_URL for TLS connections
if [ "$REDIS_URL" ] || [ "$REDIS_TEMPORARY_URL" ]
then 
    # Use REDIS_URL if available, otherwise fall back to REDIS_TEMPORARY_URL
    REDIS_CONNECTION_URL=${REDIS_URL:-$REDIS_TEMPORARY_URL}
    echo "Redis config detected: ${REDIS_CONNECTION_URL}"
    
    PREFIX="N8N_REDIS_" parse_url "$REDIS_CONNECTION_URL"
    
    # Separate host and port    
    N8N_REDIS_HOST="$(echo $N8N_REDIS_HOSTPORT | sed -e 's,:.*,,g')"
    N8N_REDIS_PORT="$(echo $N8N_REDIS_HOSTPORT | sed -e 's,^.*:,:,g' -e 's,.*:\([0-9]*\).*,\1,g' -e 's,[^0-9],,g')"
    
    # Set default Redis port if not specified
    if [ -z "$N8N_REDIS_PORT" ]; then
        N8N_REDIS_PORT=6379
        echo "No Redis port specified, using default: 6379"
    fi
    
    # Validate parsed values
    if [ -z "$N8N_REDIS_HOST" ]; then
        echo "Error: Invalid Redis URL - could not parse host"
        exit 1
    fi
    
    # Configure Queue settings
    export QUEUE_BULL_REDIS_HOST=$N8N_REDIS_HOST
    export QUEUE_BULL_REDIS_PORT=$N8N_REDIS_PORT
    export QUEUE_BULL_REDIS_PASSWORD=$N8N_REDIS_PASSWORD
    
    # Determine TLS setting from URL scheme
    if [[ "$REDIS_CONNECTION_URL" == rediss://* ]]; then
        export QUEUE_BULL_REDIS_TLS=true
        export QUEUE_BULL_REDIS_TLS_CONFIG='{}'
        echo "Redis TLS enabled with strict certificate validation"
    else
        export QUEUE_BULL_REDIS_TLS=false
        echo "Redis TLS disabled"
    fi

    # Configure Queue type
    export QUEUE_BULL_REDIS_DB=0
    export QUEUE_BULL_REDIS_TIMEOUT=5000
    export QUEUE_BULL_REDIS_RETRYINTERVAL=2000
    export QUEUE_BULL_REDIS_MAXRETRIESPERREQUEST=3
    
    echo "Redis Configuration:"
    echo "Host: $QUEUE_BULL_REDIS_HOST"
    echo "Port: $QUEUE_BULL_REDIS_PORT"
    echo "TLS: $QUEUE_BULL_REDIS_TLS"
    echo "Password: ${QUEUE_BULL_REDIS_PASSWORD:+*****}"
    echo "Timeout: $QUEUE_BULL_REDIS_TIMEOUT"
fi

# Print QUEUE_BULL_* variables
echo "QUEUE_BULL_REDIS_HOST=$QUEUE_BULL_REDIS_HOST"
echo "QUEUE_BULL_REDIS_PORT=$QUEUE_BULL_REDIS_PORT"
echo "QUEUE_BULL_REDIS_PASSWORD=$QUEUE_BULL_REDIS_PASSWORD"
echo "QUEUE_BULL_REDIS_TLS=$QUEUE_BULL_REDIS_TLS"

# kickstart nodemation worker
n8n worker