#!/bin/bash
######################################################
#         script developed by PerformanceDB          #
#             wwww.performancedb.com.br              #
######################################################
# Use when you need to know in a simple way which    #
# tables have dependencies(FK) in other tables.      #
# As simple as it may seem, sometimes need to erase  #
# data and have to stay looking the dependencies     #
# becomes a bit boring.                              #
######################################################
#             Use without moderation                 #
######################################################

source $(dirname $0)/pdbscripts.config

clear
header() {
echo '######################################################'
echo '#         script developed by PerformanceDB          #'
echo '#             wwww.performancedb.com.br              #'
echo '######################################################'
echo '# Use when you need to know in a simple way which    #'
echo '# tables have dependencies(FK) in other tables.      #'
echo '# As simple as it may seem, sometimes need to erase  #'
echo '# data and have to stay looking the dependencies     #'
echo '# becomes a bit boring.                              #'
echo '######################################################'
echo '#             Use without moderation                 #'
echo '######################################################'
}

if [ $_dbUser = ""]; then
  header
  echo ""
  echo "* You can configure the connection data in the configuration file($(dirname $0)/pdbscripts.config)"
  echo "Connection information"
  read -p "Database User: " dbUser
  read -p "Database Pass($dbUser@localhost): " dbPass
  clear
else
  dbUser=$_dbUser
  dbPass=$_dbPass
fi

header
echo ""
echo "For me to locate the dependencies, I need to know the database and the table"
read -p "Database name: " dbName
read -p "Table name: " tableName

#Stores PKs and their values
primaryKeys=()
primaryKeysValuesFirt=""

echo ""
echo "Now I will show you the primary keys of the table $dbName.$tableName and you will inform the values that you want to check the dependencies"
#Here you will enter the value of the PKs
getPksValues() {
  for pkName in $( mysql -u$dbUser -p$dbPass information_schema -e "SELECT COLUMN_NAME FROM COLUMNS WHERE TABLE_SCHEMA = '"$dbName"' AND TABLE_NAME = '"$tableName"' AND COLUMN_KEY = 'PRI'") ; do
    if [ $pkName = "COLUMN_NAME" ]; then
      continue
    fi
    read -p "Enter value of column $pkName:" pkValue
    primaryKeys+=($pkName)
    if [ "$primaryKeysValuesFirt" != "" ]; then
        primaryKeysValuesFirt+="|"
    fi
    primaryKeysValuesFirt+="$pkName:$pkValue"
  done
}
getPksValues

resultFile=$_tmpDir
resultFile+="pdb-get-data-dependency-result-$dbName-$tableName-$primaryKeysValuesFirt.sql"
resultFile=$(echo $resultFile | sed -e "s/\:/\-/g")
resultFile=$(echo $resultFile | sed -e "s/|/\-/g")
rm -rf $resultFile
data=`date +%Y-%m-%d_%H:%M:%S`
echo '-- ######################################################' >> $resultFile
echo '-- #         script developed by PerformanceDB          #' >> $resultFile
echo '-- #             wwww.performancedb.com.br              #' >> $resultFile
echo '-- ######################################################' >> $resultFile
echo '-- # Use when you need to know in a simple way which    #' >> $resultFile
echo '-- # tables have dependencies(FK) in other tables.      #' >> $resultFile
echo '-- # As simple as it may seem, sometimes need to erase  #' >> $resultFile
echo '-- # data and have to stay looking the dependencies     #' >> $resultFile
echo '-- # becomes a bit boring.                              #' >> $resultFile
echo '-- ######################################################' >> $resultFile
echo '-- #             Use without moderation                 #' >> $resultFile
echo '-- ######################################################' >> $resultFile
echo "-- " >> $resultFile
echo "-- $data" >> $resultFile
echo "-- " >> $resultFile
echo "-- ATTENTION" >> $resultFile
echo "-- this script was generated dynamically, we recommend checking before running" >> $resultFile
echo "-- " >> $resultFile
echo ""
#Embellishing the result
echo ""
echo "#####################"
echo "Dependency Hierarchy"
echo "+ "$dbName.$tableName": "$primaryKeysValuesFirt
echo -ne "We're doing the checks, this may take a few minutes."\\r
lineOff=0


#$1 = dbName
#$2 = tableName
#$3 = where
#4 = resultFile
getRecursive() (
  if [ "$1" != "" ]; then
    pksColumnCount=0
    pksList="CONCAT("
    pksListArr=()
    for pkNameRecursion in $( mysql -u$dbUser -p$dbPass information_schema -e "SELECT COLUMN_NAME FROM COLUMNS WHERE TABLE_SCHEMA = '"$1"' AND TABLE_NAME = '"$2"' AND COLUMN_KEY = 'PRI'") ; do
      if [ $pkNameRecursion = "COLUMN_NAME" ]; then
        continue
      fi
      if [ $pksColumnCount -gt 0 ]; then
        pksList+=",'|',"
      fi
      pksList+=" \"$pkNameRecursion:\",$pkNameRecursion"
      ((pksColumnCount++))
      pksListArr+=($pkNameRecursion)
    done
    pksList+=") AS pks"
    for pkValuesRecursion in $( mysql -u$dbUser -p$dbPass information_schema -e "SELECT $pksList FROM $1.$2 WHERE $3") ; do
        if [ $pkValuesRecursion = "pks" ]; then
          continue
        fi
        preparedPkList=""
        IFS='|' read -r -a preparedPkListPipe <<< $pkValuesRecursion
        for preparedPkListPipeEx in ${preparedPkListPipe[@]} ; do
                IFS=':' read -r -a preparedPkListEx <<< $preparedPkListPipeEx
                if [ "$preparedPkList" != "" ]; then
                        preparedPkList+="|"
                fi
                preparedPkList+="${preparedPkListEx[0]}:${preparedPkListEx[1]}"
        done
        getDependency $1 $2 "${preparedPkList[0]}:${preparedPkList[1]}" 2 $4
    done

  fi
  )

  #Here we will check which tables have dependency
  #$1 = dbName
  #$2 = tableName
  #$3 = pkValues
  #$4 = hierarchy
  #$5 = resultFile
  getDependency() (
    unset primaryKeysValues
    declare -A primaryKeysValues
    IFS='|' read -r -a pkValuesEx <<< $3
    for pkV in "${pkValuesEx[@]}" ; do
      IFS=':' read -r -a pkVEx <<< $pkV
      primaryKeysValues[${pkVEx[0]}]=${pkVEx[1]}
    done
    for rowsToCheck in $( mysql -u$dbUser -p$dbPass information_schema -e "SELECT CONCAT(TABLE_SCHEMA,'|',TABLE_NAME,'|',GROUP_CONCAT(COLUMN_NAME),'|',GROUP_CONCAT(REFERENCED_COLUMN_NAME)) AS fkInfo FROM KEY_COLUMN_USAGE WHERE REFERENCED_TABLE_SCHEMA = '"$1"' and REFERENCED_TABLE_NAME = '"$2"' GROUP BY TABLE_SCHEMA, TABLE_NAME") ; do
      if [ $lineOff = 0 ]; then
        echo -ne "                                                       "\\r
        lineOff=1
      fi
      if [ $rowsToCheck = "fkInfo" ]; then
        continue
      fi
      IFS='|' read -r -a fksInfo <<< $rowsToCheck
      fkDbName="${fksInfo[0]}"
      fkTableName="${fksInfo[1]}"
      IFS=',' read -r -a fkColumnName <<< ${fksInfo[2]}
      IFS=',' read -r -a fkColumnNameReference <<< ${fksInfo[3]}

      fksColumnCount=0
      where=""
      for fkColumn in "${fkColumnName[@]}" ; do
        if [ $fksColumnCount -gt 0 ]; then
          where+=" AND"
        fi
        where+=" $fkColumn = '"${primaryKeysValues[${fkColumnNameReference[$fksColumnCount]}]}"'"
        ((fksColumnCount++))
      done
      for qtdBlockingLines in $( mysql -u$dbUser -p$dbPass information_schema -e "SELECT COUNT(*) AS qtdRows FROM $fkDbName.$fkTableName WHERE $where") ; do
        if [ $qtdBlockingLines = "qtdRows" ]; then
          continue
        fi
        if [ $qtdBlockingLines -gt 0 ]; then
          hierarchy=""
          for i in `seq 1 $4`; do
                  hierarchy+="    "
          done
          echo "$hierarchy|"
          echo "$hierarchy+-- $fkDbName.$fkTableName [$qtdBlockingLines Dependency found]"
          getRecursive $fkDbName $fkTableName "$where" $5
          echo "DELETE FROM $fkDbName.$fkTableName WHERE $where;" >> $5
        fi
      done

    done
  )
  getDependency $dbName $tableName $primaryKeysValuesFirt 1 $resultFile
  echo "#####################"
  echo ""
  echo "###################################################################"
  echo "We generate a file with the commands to shut down all dependencies."
  echo "Result File: "$resultFile" <<-------------------------------------------- LOOK oO"
  echo "###################################################################"

  #The End


echo ""
echo ""
echo "If you find a bug or have suggestions, send us an email, I'm sure we'll love to respond."
echo "scripts@performanceb.com.br"
echo "bye bye :)"
echo ""
