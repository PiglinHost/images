#!/bin/bash

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the container's working directory
cd /home/container || exit 1

# Print Java version
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mjava -version\n"
java -version

# FORGE Install
# Directory to search for .jar files
search_directory="/home/container/"

# Find all .jar files in /home/container and check if they contain "/minecraftforge/installer/"
find "$search_directory" -maxdepth 1 -type f -name "*.jar" ! -name "*_installed.jar" -exec bash -c '
    if jar tf "$0" | grep -q "/minecraftforge/installer/" && [[ "$0" != *_installed.jar ]]; then
        java -jar "$0" --installServer
        mv "$0" "${0%.jar}_installed.jar"
    fi
' {} \;

# automatikus sh inditas ha java @ az utolso sorban megtalalhato cmd=$(tail -n 1 $run | grep -m1 "java")
foundSH=0
START=('start.sh' 'run.sh' 'ServerStart.sh' 'ServerInstall.sh' 'startserver.sh')

# Memory value to replace with
SERVER_MEMORY=${SERVER_MEMORY}

for run in "${START[@]}"; do
  if [ -f "$run" ]; then
    # Replace # (if present) and space before -Xmx?G with -Xmx{{SERVER_MEMORY}}M
    sed -i -E 's/#?\s*-Xmx[0-9]+[GM]/ -Xmx'"$SERVER_MEMORY"M'/g' "$run"
    #echo "Replaced memory settings in $run"

    cmd=$(grep -r --include=\*.sh -E "java|JAVA|javas|JAVAS")
    if [ ! -z "$cmd" ]; then
      # Define the directories to search in
      directories=("/home/container/libraries" "/home/container")

      # Loop through the directories
      for dir in "${directories[@]}"; do
        # Search for user_jvm_args.txt files
        jvm_args_files=$(find "$dir" -type f -name "user_jvm_args.txt")

        # Loop through the found files
        for file in $jvm_args_files; do
          # Replace # (if present) and space before -Xmx?G with -Xmx{{SERVER_MEMORY}}M
          sed -i -E 's/#?\s*-Xmx[0-9]+[GM]/ -Xmx'"$SERVER_MEMORY"M'/g' "$file"
          #echo "Replaced memory settings in $file"
        done
      done

      echo "SH fájl futtatása"
      echo "eula=true" >> eula.txt
      foundSH=1
      bash "$run"
	  exit
    fi
    break
  fi
done

#FORGE Install
# Directory to search for .jar files
search_directory="/home/container/"

# Find all .jar files in /home/container and check if they contain "/minecraftforge/installer/"
find "$search_directory" -maxdepth 1 -type f -name "*.jar" -a ! -name "*_installed.jar" -exec bash -c '
    jar_file="$0"
    # Extract version.json and read "inheritsFrom"
    if jar xf "$jar_file" version.json 2>/dev/null; then
        version=$(grep -oP "\"inheritsFrom\": \"\\K[0-9.]+\"" version.json)
        rm -f version.json

		# Additional processing if required
        if grep -q "/minecraftforge/installer/" "$jar_file"; then
            echo "Running installer for $jar_file..."
            java -jar "$jar_file" --installServer
            mv "$jar_file" "${jar_file%.jar}_installed.jar"
        fi

		if [[ -n "$version" ]]; then
            echo "Found version: $version in $jar_file"

            # Compare version with 1.16.5
            if [[ "$(printf "%s\n%s" "$version" "1.16.6" | sort -V | head -n 1)" == "$version" && "$version" != "1.16.6" ]]; then
                echo "Version $version is lower than 1.17"
				echo "eula=true" >> eula.txt
				mv forge-*.jar server.jar
            else
                echo "Version $version is 1.17 or higher"
            fi
        else
            echo "No version found in $jar_file"
        fi
    else
        echo "version.json not found in $jar_file"
    fi
' {} \;

# FTB Install
find "." -maxdepth 1 -type f -name "*" ! -name "*_installed" -print0 |
while IFS= read -r -d '' file; do
    # Check if the file is executable
    if [ -x "$file" ]; then
        # Check if "creeperhost.net" is present in the file content
        if grep -q "creeperhost.net" "$file" && [[ "$file" != *_installed ]]; then
            # Run the executable file
            ./$file --path /home/container --nojava
            # Move the file to a new name with "_installed" suffix
            mv "$file" "${file}_installed"
			exit
        fi
    fi
done


# Forge Server run
found_file=$(find . -maxdepth 1 -type f -name 'forge-*-universal.jar')
if [ -n "$found_file" ]; then
  OLD_SERVER_JARFILE=${SERVER_JARFILE}
  SERVER_JARFILE="$found_file"
  echo "${OLD_SERVER_JARFILE} updated to: $SERVER_JARFILE"
fi

# Convert all of the "{{VARIABLE}}" parts of the command into the expected shell
# variable format of "${VARIABLE}" before evaluating the string and automatically
# replacing the values.
PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

# Display the command we're running in the output, and then execute it with the env from the container itself.
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"

# Run the server
exec env ${PARSED}
