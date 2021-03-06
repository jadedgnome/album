#!/bin/bash
# This variant of gallery.sh has a slightly different calling format
# The source directory is relative to the cwd, NOT the root of the web
#
# It also creates an originals directory with hard links to the original
# files.  This enables the originals to reside on the file system in a
# place not accessible to the web server.
# The originals can now be in an ftp directory.  It's not safe to have
# an ftp directory accessible via the web.

ORIGINALS_SUBDIR='original'
PREVIEW_SUBDIR='preview'
PREVIEW_SIZE='800'
PREVIEW_FORMAT='jpg'
THUMB_SUBDIR='thumbnail'
THUMB_SIZE='200'
INDEX_NAME='index'
ALBUM_THUMBNAIL_NAME='album_thumbnail.jpg'

if [ ! -d "$1" -o ! -d "$2" -o "" = "$3" ]; then
  echo 'Specify the root directory of the web (absolute, or relative to cwd)'
  echo 'Specify a source directory (absolute, or relative to cwd)'
  echo 'Specify a destination directory relative to the root of the web'
  echo 'An optional fourth parameter is a title for link to the index file in the parent directory'
  echo 'An optional fifth parameter is the link value to the index file in the parent directory, defaults to "../index.html"'
  exit 1
fi

ROOT_DIR="$1"
SOURCE_DIR="$2"
DEST_REL_DIR="$3"
shift 3
DEST_DIR="${ROOT_DIR}/${DEST_REL_DIR}"
PREVIEW_DIR="${DEST_DIR}/${PREVIEW_SUBDIR}"
THUMB_DIR="${DEST_DIR}/${THUMB_SUBDIR}"
ORIG_DIR="${DEST_DIR}/${ORIGINALS_SUBDIR}"

[ -e "$DEST_DIR" ] || mkdir -p "$DEST_DIR"
[ -e "$ORIG_DIR" ] || mkdir "$ORIG_DIR"
[ -e "$PREVIEW_DIR" ] || mkdir "$PREVIEW_DIR"
[ -e "$THUMB_DIR" ] || mkdir "$THUMB_DIR"
if [ -d "$PREVIEW_DIR" -a -d "$THUMB_DIR" -a -d "$ORIG_DIR" ]; then
  # make preview and thumbnail images
  # make hard links to originals
  PHOTO_COUNT=0
  while IFS= read -d $'\0' -r SRC_IMAGE ; do
    CURF=${SRC_IMAGE##*/}
    DEST_PREVIEW="$PREVIEW_DIR/$CURF"
    DEST_THUMB="$THUMB_DIR/$CURF"
    DEST_ORIG="$ORIG_DIR/$CURF"
    [ "$SRC_IMAGE" -nt "$DEST_PREVIEW" ] && echo "$DEST_PREVIEW" && convert "$SRC_IMAGE" \
      -auto-orient \
      -resize ${PREVIEW_SIZE}x${PREVIEW_SIZE} \
      "$DEST_PREVIEW"
    [ "$SRC_IMAGE" -nt "$DEST_THUMB" ] && echo "$DEST_THUMB" && convert "$SRC_IMAGE" \
      -auto-orient \
      -resize ${THUMB_SIZE}x${THUMB_SIZE} \
      "$DEST_THUMB"
    [ -e "$DEST_ORIG" ] && rm "$DEST_ORIG"
    link "$SRC_IMAGE" "$DEST_ORIG"
    PHOTO_LIST[$PHOTO_COUNT]="$CURF"
    PHOTO_COUNT=$((PHOTO_COUNT+1))
  done < <(find -L "$SOURCE_DIR" -maxdepth 1 \( -iname '*.jpg' \
     -o -iname '*.jpeg' \
     -o -iname '*.gif' \
     -o -iname '*.png' \) \
     -a -type f -print0 | sort -z )

  # make album thumbnail
  if [ 0 -lt $PHOTO_COUNT ]; then
    SRC_IMAGE="$SOURCE_DIR/${PHOTO_LIST[0]}"
    DEST_IMAGE="$DEST_DIR/$ALBUM_THUMBNAIL_NAME"
    [ "$SRC_IMAGE" -nt "$DEST_IMAGE" ] && echo "$DEST_IMAGE" && convert "$SRC_IMAGE" \
      -auto-orient \
      -resize ${THUMB_SIZE}x${THUMB_SIZE} \
      "$DEST_IMAGE"
  fi

  # make sub-albums
  DIR_COUNT=0
  while IFS= read -d $'\0' -r SRC_DIR ; do
    DIR=${SRC_DIR##*/}
    $0 "$ROOT_DIR" "$SOURCE_DIR/$DIR" "$DEST_REL_DIR/$DIR" "${DEST_REL_DIR##*/}"
    DIR_LIST[$DIR_COUNT]="$DIR"
    DIR_COUNT=$((DIR_COUNT+1))
  done < <(find -L "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z) 

  # output preview pages
  for (( CUR_PHOTO=0 ; $CUR_PHOTO < $PHOTO_COUNT ; CUR_PHOTO=$((CUR_PHOTO+1)) )) do
    CUR_PHOTO_NAME=${PHOTO_LIST[$CUR_PHOTO]}
    CUR_PHOTO_REF=$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "${CUR_PHOTO_NAME}")
    ORIG_IMAGE="$ORIGINALS_SUBDIR/$CUR_PHOTO_REF"
    DEST_PREVIEW="$PREVIEW_SUBDIR/$CUR_PHOTO_REF"
    DEST_THUMB="$THUMB_SUBDIR/$CUR_PHOTO_REF"
    NAME=${CUR_PHOTO_NAME%.*}
    PREVIEW_XML=$DEST_DIR/$NAME.xml
    echo "$PREVIEW_XML"
    cat > "$PREVIEW_XML" <<EOF
<?xml version='1.0' ?>
<image-preview>
  <thumbnail src="$DEST_THUMB"/>
  <image src="$DEST_PREVIEW"/>
  <full-size src="$ORIG_IMAGE"/>
  <index loc="$INDEX_NAME.html#photo$CUR_PHOTO"/>
EOF
    if [ $CUR_PHOTO -gt 0 ]; then
      PREVIOUS=${PHOTO_LIST[(($CUR_PHOTO-1))]}
      PREVIOUS_REF=$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "${PREVIOUS}")
      cat >> "$PREVIEW_XML" <<EOF
  <previous loc="${PREVIOUS_REF%.*}.html">
    <thumbnail src="$THUMB_SUBDIR/$PREVIOUS_REF"/>
  </previous>
EOF
    fi
    if [ $CUR_PHOTO -lt $((PHOTO_COUNT-1)) ]; then
      NEXT=${PHOTO_LIST[(($CUR_PHOTO+1))]}
      NEXT_REF=$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "${NEXT}")
      cat >> "$PREVIEW_XML" <<EOF
  <next loc="${NEXT_REF%.*}.html">
    <thumbnail src="$THUMB_SUBDIR/$NEXT_REF"/>
  </next>
EOF
    fi
    cat >> "$PREVIEW_XML" <<EOF
</image-preview>
EOF
  done # for CUR_PHOTO

  # output index page
  INDEX_XML="$DEST_DIR/$INDEX_NAME.xml"
  echo "$INDEX_XML"
  cat > "$INDEX_XML" <<EOF
<?xml version='1.0' ?>
<album title="${DEST_REL_DIR##*/}">
EOF

  # output parent
  if [ 0 -lt $# ]; then
    if [ 1 -lt $# ]; then
      INDEX_LINK=$2
    else
      INDEX_LINK="../${INDEX_NAME}.html"
    fi
    cat >> "$INDEX_XML" <<EOF
  <parent title="$1" link="${INDEX_LINK}"/>
EOF
  fi

  for (( CUR_DIR=0 ; $CUR_DIR < $DIR_COUNT ; CUR_DIR=$((CUR_DIR+1)) )) do
    CUR_DIR_NAME=$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "${DIR_LIST[$CUR_DIR]}")
    cat >> "$INDEX_XML" <<EOF
  <sub-album loc="$CUR_DIR_NAME/$INDEX_NAME.html">
    <thumbnail src="$CUR_DIR_NAME/$ALBUM_THUMBNAIL_NAME">
      ${DIR_LIST[$CUR_DIR]}
    </thumbnail>
  </sub-album>
EOF
  done

  for (( CUR_PHOTO=0 ; $CUR_PHOTO < $PHOTO_COUNT ; CUR_PHOTO=$((CUR_PHOTO+1)) )) do
    CUR_PHOTO_NAME=${PHOTO_LIST[$CUR_PHOTO]}
    CUR_PHOTO_REF=$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "${CUR_PHOTO_NAME}")
    DEST_THUMB="$THUMB_SUBDIR/$CUR_PHOTO_REF"
    NAME=${CUR_PHOTO_REF%.*}
    PREVIEW_NAME="$NAME.html"
    cat >> "$INDEX_XML" <<EOF
  <preview
    id="photo$CUR_PHOTO"
    loc="$PREVIEW_NAME">
    <thumbnail src="$DEST_THUMB">
      $(echo ${CUR_PHOTO_NAME%.*} | sed -e 's/&/&amp;/g')
    </thumbnail>
  </preview>
EOF
  done
  cat >> "$INDEX_XML" <<EOF
</album>
EOF

else
  echo 'failed to create scaled image directory. file in the way?'
fi

