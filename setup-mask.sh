#!/bin/bash
#
# masking_setup.sh
# Created: Paulo Victor Maluf - 09/2019
#
# Parameters:
#
#   masking_setup.sh --help
#
#    Parameter             Short Description                                                        Default
#    --------------------- ----- ------------------------------------------------------------------ ---------------
#    --profile-name           -p Profile name
#    --application-name       -a Application Name
#    --environment-name       -e Environment Name
#    --expressions-file       -f Delimiter file like: ExpressionName;DomainName;level;Regex         expressions.cfg               
#    --domains-file           -d Delimiter file like: Domain Name;Classification;Algorithm          domains.cfg 
#    --connection-file        -c Delimiter file like: connectorName;databaseType;environmentId;     connections.cfg
#                                                     host;password;port;schemaName;sid;username 
#    --masking-engine         -m Masking Engine Address
#    --help                   -h help
#
#   Ex.: masking_setup.sh --profile-name LGPD -a HR -e HR -f ./expressions.csv -d ./domains.cfg -c ./connections.cfg -m 172.168.8.128
#
# Changelog:
#
# Date       Author               Description
# ---------- ------------------- ----------------------------------------------------
#====================================================================================

################################
# VARIAVEIS GLOBAIS            #
################################
USERNAME="Admin"
PASSWORD="Admin-12"
LAST=".last"

################################
# FUNCOES                      #
################################
help()
{
  head -21 $0 | tail -19
  exit
}

log (){
  echo -ne "[`date '+%d%m%Y %T'`] $1" | tee -a ${LAST}
}

# Check if $1 is equal to 0. If so print out message specified in $2 and exit.
check_empty() {
    if [ $1 -eq 0 ]; then
        echo $2
        exit 1
    fi
}

# Check if $1 is an object and if it has an 'errorMessage' specified. If so, print the object and exit.
check_error() {
    # jq returns a literal null so we have to check againt that...
    if [ "$(echo "$1" | jq -r 'if type=="object" then .errorMessage else "null" end')" != 'null' ]; then
        echo $1
        exit 1
    fi
}

# Login and set the correct $AUTH_HEADER.
login() {
echo "* logging in..."
LOGIN_RESPONSE=$(curl -s -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- $MASKING_ENGINE/login <<EOF
{
    "username": "$USERNAME",
    "password": "$PASSWORD"
}
EOF
)
    check_error "$LOGIN_RESPONSE"
    TOKEN=$(echo $LOGIN_RESPONSE | jq -r '.Authorization')
    AUTH_HEADER="Authorization: $TOKEN"
}

create_application(){
APPLICATIONNAME=${1}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/applications <<EOF
{
  "applicationName": "${APPLICATIONNAME}"
}
EOF
}

create_environment(){
ENVIRONMENTNAME=${1}
APPLICATIONNAME=${2}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/environments <<EOF
{
  "environmentName": "${ENVIRONMENTNAME}",
  "application": "${APPLICATIONNAME}",
  "purpose": "MASK"
}
EOF
}

get_environmentid(){
ENVIRONMENTNAME=${1}
RESPONSE=$(curl -s -X GET -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' ${MASKING_ENGINE}/environments)
check_error ${RESPONSE}

ENVIRONMENTID=$(echo ${RESPONSE} | jq -r ".responseList[] | select(.environmentName == \"${ENVIRONMENTNAME}\") | .environmentId")

echo ${ENVIRONMENTID}
}

add_expression(){
DOMAIN=${1}
EXPRESSNAME=${2}
REGEXP=${3}
DATALEVEL=${4}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/profile-expressions <<EOF
{
  "domainName": "${DOMAIN}",
  "expressionName": "${EXPRESSNAME}",
  "regularExpression": "${REGEXP}",
  "dataLevelProfiling": ${DATALEVEL}
}
EOF
}

add_domain(){
NEW_DOMAIN=${1}
CLASSIFICATION=${2}
ALGORITHM=${3}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/domains <<EOF
{
  "domainName": "${NEW_DOMAIN}",
  "classification": "${CLASSIFICATION}",
  "defaultAlgorithmCode": "${ALGORITHM}"
}
EOF
}

add_profileset(){
PROFILENAME=${1}
EXPRESSID=${2}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/profile-sets <<EOF
{
  "profileSetName": "${PROFILENAME}",
  "profileExpressionIds": [ ${EXPRESSID} ]
}
EOF
}

create_connection(){
CONNECTORNAME=${1}
DATABASETYPE=${2}
ENVIRONMENTID=${3}
HOST=${4}
PORT=${5}
SID=${6}
USERNAME=${7}
PASSWORD=${8}
SCHEMANAME=${9}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/database-connectors <<EOF
{
  "connectorName": "${CONNECTORNAME}",
  "databaseType": "${DATABASETYPE}",
  "environmentId": ${ENVIRONMENTID},
  "host": "${HOST}",
  "password": "${PASSWORD}",
  "port": ${PORT},
  "schemaName": "${SCHEMANAME}",
  "sid": "${SID}",
  "username": "${USERNAME}"
}
EOF
}

get_connectorid(){
CONNECTORNAME=${1}
CONNECTORLIST=$(curl -s -X GET -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' ${MASKING_ENGINE}/database-connectors)
CONNECTORID=$(echo ${CONNECTORLIST} | jq -r ".responseList[] | select(.connectorName == \"${CONNECTORNAME}\") | .databaseConnectorId")
echo ${CONNECTORID}
}

create_ruleset(){
RULESETNAME=${1}
DATABASECONNECTORID=${2}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/database-rulesets <<EOF
{
  "rulesetName": "${RULESETNAME}",
  "databaseConnectorId": ${DATABASECONNECTORID}
}
EOF
}

get_rulesetid(){
  RULESETNAME=${1}
  RET=$(curl -s -X GET -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' ${MASKING_ENGINE}/database-rulesets)
  check_error ${RET}
  RESULTSETID=$(echo ${RET} | jq -r ".responseList[] | select(.rulesetName == \"${RULESETNAME}\") | .databaseRulesetId")
  echo ${RESULTSETID}
}

create_tablemetadata(){
TABLENAME=${1}
RULESETID=${2}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/table-metadata <<EOF
{
  "tableName": "${TABLENAME}",
  "rulesetId": ${RULESETID},
  "keyColumn": "ROWID"
}
EOF
}

get_tables(){
  CONNECTORID=${1}
  RET=$(curl -s -X GET -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' ${MASKING_ENGINE}/database-connectors/${CONNECTORID}/fetch)
  check_error ${RET}
  TABLES=$(echo ${RET} | jq ".[]" | xargs)
  echo ${TABLES}
}

get_profilesetid(){
PROFILESETNAME=${1}

RESPONSE=$(curl -s -X GET -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' ${MASKING_ENGINE}/profile-sets)
check_error ${RESPONSE}
PROFILESETID=$(echo ${RESPONSE} | jq -r ".responseList[] | select(.profileSetName == \"${PROFILESETNAME}\") | .profileSetId")

echo ${PROFILESETID}
}

create_profilejob(){
PROFILEJOBNAME=${1}
PROFILESETID=${2}
RULESETID=${3}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/profile-jobs <<EOF
{
  "jobName": "${PROFILEJOBNAME}",
  "profileSetId": ${PROFILESETID},
  "rulesetId": ${RULESETID},
  "feedbackSize": 50000,
  "minMemory": 1024,
  "maxMemory": 4096,
  "numInputStreams": 5
}
EOF
}

create_maskjob(){
MASKJOBNAME=${1}
RULESETID=${2}

curl -s -X POST -H ''"${AUTH_HEADER}"'' -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- ${MASKING_ENGINE}/masking-jobs <<EOF
{
  "jobName": "${MASKJOBNAME}",
  "rulesetId": ${RULESETID},
  "feedbackSize": 100000,
  "onTheFlyMasking": false,
  "databaseMaskingOptions": {
    "batchUpdate": true,
    "commitSize": 50000,
    "dropConstraints": false,
    "minMemory": 1024,
    "maxMemory": 4096,
    "numInputStreams": 5
  }
}
EOF
}

################################
# ARGPARSER                    #
################################
# Verifica se foi passado algum parametro
[ "$1" ] || { help ; exit 1 ; }

# Verifica se o jq esta instalado
[ -x "$(which jq)" ] || { echo "jq not found. Please install 'jq' package and try again." ; exit 1 ; }

# Tratamento dos Parametros
for arg
do
    delim=""
    case "$arg" in
    #translate --gnu-long-options to -g (short options)
      --profile-name)         args="${args}-p ";;
      --application-name)     args="${args}-a ";;
      --environment-name)     args="${args}-e ";;
      --expressions-file)     args="${args}-f ";;
      --domains-file)         args="${args}-d ";;
      --connection-file)      args="${args}-c ";;
      --ruleset-file)         args="${args}-r ";;
      --masking-engine)       args="${args}-m ";;
      --help)                 args="${args}-h ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
         args="${args}${delim}${arg}${delim} ";;
    esac
done

eval set -- $args

while getopts ":hp:e:d:m:c:r:a:f:" PARAMETRO
do
    case $PARAMETRO in
        h) help;;
        p) PROFILENAME=${OPTARG[@]};;
        a) APPLICATIONNAME=${OPTARG[@]};;
        e) ENVIRONMENTNAME=${OPTARG[@]};;
        f) EXPRESSFILE=${OPTARG[@]};;
        d) DOMAINSFILE=${OPTARG[@]};;
        c) CONNECTIONFILE=${OPTARG[@]};;
        r) RULESETFILE=${OPTARG[@]};;
        m) MASKING_ENGINE=${OPTARG[@]};;
        :) echo "Option -$OPTARG requires an argument."; exit 1;;
        *) echo $OPTARG is an unrecognized option ; echo $USAGE; exit 1;;
    esac
done

################################
# MAIN                         #
################################
if [ -e ${EXPRESSFILE} ] && [ -e ${DOMAINSFILE} ] && [ ${MASKING_ENGINE} ]
  then
    # Set masking engine variable from user input
    MASKING_ENGINE="http://${MASKING_ENGINE}/masking/api"
    
    # Login on Masking Engine
    login

    # Create masking application
    log "Creating application ${APPLICATIONNAME}...\n"
    ret=$(create_application ${APPLICATIONNAME})
    check_error ${ret}

    # Create masking environment 
    log "Creating environment ${ENVIRONMENTNAME}...\n"
    ret=$(create_environment ${ENVIRONMENTNAME} ${APPLICATIONNAME})
    check_error ${ret}

    # Create Domains 
    log "Creating domain ${NEW_DOMAIN}...\n"
    while IFS=\; read -r NEW_DOMAIN CLASSIFICATION ALGORITHM
    do
      if [[ ! ${NEW_DOMAIN} =~ "#" ]]
        then
          ret=$(add_domain ${NEW_DOMAIN} ${CLASSIFICATION} ${ALGORITHM})
      fi
    done < ${DOMAINSFILE}

    # Create Expressions 
    log "Creating expressions: \n"
    while IFS=\; read -r EXPRESSNAME DOMAIN DATALEVEL REGEXP
    do
      if [[ ! ${EXPRESSNAME} =~ "#" ]]
        then
          log "* ${EXPRESSNAME}\n" 0
          ret=$(add_expression ${DOMAIN} ${EXPRESSNAME} ${REGEXP} ${DATALEVEL} | tee -a $$.tmp)
      fi
    done < ${EXPRESSFILE}
  
    # Get Created Expression Ids
    # 7 - Creditcard
    # 8 - Creditcard
    # 11 - Email
    # 22 - Creditcard Data
    # 23 - Email Data
    # 49 - Ip Address Data
    # 50 - Ip Address
    EXPRESSID=$(egrep -o '"profileExpressionId":[0-9]+' $$.tmp | cut -d: -f2 | xargs | sed 's/ /,/g')
    EXPRESSID="7,8,11,22,23,49,50,${EXPRESSID}"
    
    # Add ProfileSet
    log "Adding expressions ids ${EXPRESSID} to ${PROFILENAME}...\n"
    ret=$(add_profileset "${PROFILENAME}" "${EXPRESSID}")

    # remove tmpfile
    rm -f $$.tmp
    
    # Create connection environment
    log "Getting environment id for ${ENVIRONMENTNAME}...\n"
    ENVIRONMENTID=$(get_environmentid ${ENVIRONMENTNAME})

    while IFS=\; read -r CONNECTORNAME DATABASETYPE HOST PORT SID USERNAME PASSWORD SCHEMANAME
    do
      if [[ ! ${CONNECTORNAME} =~ "#" ]]
        then
          log "Creating connection ${CONNECTORNAME} for environment ${ENVIRONMENTNAME}...\n"
          ret=$(create_connection ${CONNECTORNAME} ${DATABASETYPE} ${ENVIRONMENTID} ${HOST} ${PORT} ${SID} ${USERNAME} ${PASSWORD} ${SCHEMANAME})
          check_error ${ret}

          log "Getting connector id for ${CONNECTORNAME}...\n"
          CONNECTORID=$(get_connectorid ${CONNECTORNAME})

          # Create RuleSet 
          RULESETNAME="RS_${CONNECTORNAME}"
          log "Creating ruleset ${RULESETNAME}...\n"
          ret=$(create_ruleset ${RULESETNAME} ${CONNECTORID})
          check_error ${ret}

          log "Getting ruleset id for ${RULESETNAME}\n"
          RULESETID=$(get_rulesetid ${RULESETNAME})

          log "Getting tables from ${CONNECTORNAME} schema...\n"
          TABLES=$(get_tables ${CONNECTORID})

          log "Creating metadata for table:\n"
          for TABLE in ${TABLES}
          do
            log "* ${TABLE}\n"
            ret=$(create_tablemetadata ${TABLE} ${RULESETID})
            check_error ${ret}
          done

          # Create Job Profile
          log "Getting profileset id ...\n"
          PROFILESETID=$(get_profilesetid ${PROFILENAME})
        
          log "Creating profile job PR_JOB_${CONNECTORNAME}...\n"
          ret=$(create_profilejob "PR_JOB_${CONNECTORNAME}" ${PROFILESETID} ${RULESETID})
          check_error ${ret}

          # Create Masking Job
          log "Creating masking job MSK_JOB_${CONNECTORNAME}...\n"
          ret=$(create_maskjob "MSK_JOB_${CONNECTORNAME}" ${RULESETID})
          check_error ${ret}
      fi
    done < ${CONNECTIONFILE}    
fi
