{ writeShellApplication
, coreutils
, cryptsetup
, gawk
, gnugrep
, yubikey-personalization
}:

writeShellApplication {
  name = "ykfde-open";

  runtimeInputs = [
    coreutils
    cryptsetup
    gawk
    gnugrep
    yubikey-personalization
  ];

  text = ''
    YKFDE_LUKS_DEV=""
    YKFDE_LUKS_KEYSLOT=""
    YKFDE_LUKS_NAME=""
    YKFDE_PRINT_ONLY=""
    YKFDE_TEST_PASSPHRASE=""
    DBG=""
    YKFDE_CHALLENGE_SLOT="2"
    YKFDE_CHALLENGE=""
    YKFDE_CHALLENGE_PASSWORD_NEEDED=""
    YKFDE_RESPONSE=""
    YKFDE_PASSPHRASE=""

    usage() {
      cat <<'USAGE'
     -d  : select an existing LUKS device or image file
     -s  : select the LUKS keyslot
     -n  : set the mapped encrypted volume name
     -p  : show cleartext ykfde passphrase without unlocking
     -t  : test LUKS passphrase
     -v  : show input/output in cleartext
     [ -- --params ] : pass optional cryptsetup luksOpen parameters
    USAGE
    }

    if [ -r /etc/ykfde.conf ]; then
      # shellcheck source=/dev/null
      . /etc/ykfde.conf
    else
      echo "WARNING: Can't access /etc/ykfde.conf. Falling back to defaults."
    fi

    while getopts ":d:s:n:ptvh" opt; do
      case "$opt" in
        d)
          YKFDE_LUKS_DEV="$OPTARG"
          printf '%s\n' "INFO: Setting device to '$OPTARG'."
          ;;
        s)
          if [ "$OPTARG" -ge 0 ] && [ "$OPTARG" -le 7 ]; then
            YKFDE_LUKS_KEYSLOT="$OPTARG"
            printf '%s\n' "INFO: Setting LUKS keyslot to '$OPTARG'."
          else
            printf '%s\n' "ERROR: Chosen LUKS keyslot '$OPTARG' is invalid."
            printf '%s\n' "Please choose a valid LUKS keyslot number between '0-7'."
            exit 1
          fi
          ;;
        n)
          YKFDE_LUKS_NAME="$OPTARG"
          printf '%s\n' "INFO: Setting name to '$OPTARG'."
          ;;
        p)
          YKFDE_PRINT_ONLY=1
          echo "INFO: Showing cleartext ykfde passphrase without unlocking"
          ;;
        t)
          YKFDE_TEST_PASSPHRASE=1
          echo "INFO: Testing LUKS passphrase"
          ;;
        v)
          DBG=1
          echo "INFO: Debugging enabled"
          ;;
        h)
          usage
          exit 0
          ;;
        \?)
          printf '%s\n' "ERROR: Invalid option: '-$OPTARG'" >&2
          usage
          exit 1
          ;;
      esac
    done
    shift "$((OPTIND - 1))"

    YKFDE_SLOT_CHECK="$(ykinfo -q -"$YKFDE_CHALLENGE_SLOT" || true)"
    if [ -n "$DBG" ]; then
      printf '%s\n' " > YubiKey slot status 'ykinfo -q -$YKFDE_CHALLENGE_SLOT': $YKFDE_SLOT_CHECK"
    fi

    if [ "$YKFDE_SLOT_CHECK" != 1 ]; then
      printf '%s\n' "ERROR: Chosen YubiKey slot '$YKFDE_CHALLENGE_SLOT' isn't configured."
      printf '%s\n' "Please choose a slot configured for HMAC-SHA1 Challenge-Response mode in '/etc/ykfde.conf'."
      exit 1
    fi

    if [ -z "$YKFDE_PRINT_ONLY" ]; then
      if [ -z "$YKFDE_LUKS_DEV" ]; then
        echo "ERROR: Device not selected. Use '-d', see 'ykfde-open -h' for help."
        exit 1
      fi

      if [ ! -e "$YKFDE_LUKS_DEV" ]; then
        printf '%s\n' "ERROR: Selected device '$YKFDE_LUKS_DEV' doesn't exist."
        exit 1
      fi

      if ! cryptsetup isLuks "$YKFDE_LUKS_DEV" "$@"; then
        printf '%s\n' "ERROR: Selected device '$YKFDE_LUKS_DEV' isn't a LUKS encrypted volume."
        exit 1
      fi

      if [ -z "$YKFDE_TEST_PASSPHRASE" ] && [ -z "$YKFDE_LUKS_NAME" ]; then
        printf '%s\n' "ERROR: Please set the mapped volume name using '-n', see 'ykfde-open -h' for help."
        exit 1
      fi

      if [ -n "$YKFDE_LUKS_NAME" ]; then
        printf '%s\n' "WARNING: This script will try to open '$YKFDE_LUKS_DEV' as '/dev/mapper/$YKFDE_LUKS_NAME'."
      fi
    fi

    if [ -z "$YKFDE_CHALLENGE" ]; then
      YKFDE_CHALLENGE_PASSWORD_NEEDED=1
    fi

    while [ -z "$YKFDE_CHALLENGE" ]; do
      echo " > Please provide the challenge."
      printf " Enter challenge: "
      if [ -n "$DBG" ]; then
        read -r YKFDE_CHALLENGE
      else
        read -r -s YKFDE_CHALLENGE
      fi
      YKFDE_CHALLENGE="$(printf %s "$YKFDE_CHALLENGE" | sha256sum | awk '{print $1}')"
      if [ -z "$DBG" ]; then
        echo
      fi
    done

    while [ -z "$YKFDE_RESPONSE" ]; do
      if [ -n "$DBG" ]; then
        printf '%s\n' " Running: 'ykchalresp -$YKFDE_CHALLENGE_SLOT $YKFDE_CHALLENGE'..."
      fi
      echo " Remember to touch the device if necessary."
      YKFDE_RESPONSE="$(printf %s "$YKFDE_CHALLENGE" | ykchalresp -"$YKFDE_CHALLENGE_SLOT" -i- | tr -d '\n')" || true
      if [ -n "$DBG" ]; then
        printf '%s\n' " Received response: '$YKFDE_RESPONSE'"
      fi
    done

    if [ -n "$YKFDE_CHALLENGE_PASSWORD_NEEDED" ]; then
      YKFDE_PASSPHRASE="$YKFDE_CHALLENGE$YKFDE_RESPONSE"
    else
      YKFDE_PASSPHRASE="$YKFDE_RESPONSE"
    fi

    if [ -n "$YKFDE_PRINT_ONLY" ]; then
      printf '%s\n' " > ykfde passphrase: $YKFDE_PASSPHRASE"
      exit 0
    fi

    cryptsetup_args=()
    if [ -n "$YKFDE_LUKS_KEYSLOT" ]; then
      cryptsetup_args+=("--key-slot=$YKFDE_LUKS_KEYSLOT")
    fi
    cryptsetup_args+=("$@")

    if [ -n "$YKFDE_TEST_PASSPHRASE" ]; then
      if [ -n "$DBG" ]; then
        printf '%s\n' " > Testing passphrase with cryptsetup."
      else
        echo " > Testing passphrase with cryptsetup..."
      fi
      printf %s "$YKFDE_PASSPHRASE" | cryptsetup open --test-passphrase "$YKFDE_LUKS_DEV" --key-file - "''${cryptsetup_args[@]}"
      printf '%s\n' " Passphrase test successful"
      exit 0
    fi

    if [ "$(id -u)" -ne 0 ]; then
      printf '%s\n' "ERROR: This NixOS-packaged ykfde-open is intended for root cryptsetup use."
      printf '%s\n' "For LUKS image files, run it with sudo."
      exit 1
    fi

    if [ -n "$DBG" ]; then
      printf '%s\n' " > Decrypting with cryptsetup luksOpen."
    else
      echo " > Decrypting with cryptsetup..."
    fi

    printf %s "$YKFDE_PASSPHRASE" | cryptsetup luksOpen "$YKFDE_LUKS_DEV" "$YKFDE_LUKS_NAME" --key-file - "''${cryptsetup_args[@]}"
    printf '%s\n' " Device successfully opened as '/dev/mapper/$YKFDE_LUKS_NAME'"
  '';
}
