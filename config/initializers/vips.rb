# frozen_string_literal: true

# libvips decodes JPEG, PNG and HEIF only, in every process. It picks a decoder from
# a file's bytes, not its name or Content-Type, and the image's other decoders (TIFF,
# OpenEXR, PDF, GIF, WebP...) carry unfixed CVEs. Member photo uploads are the only
# untrusted files it opens (PhotoUploadConcern#accepted_photo?); everything else is a
# JPEG the app wrote. Blocked decoders are skipped, so a JPEG another loader would
# claim first (UltraHDR in libvips 8.18) still opens as a JPEG.
Vips.block("VipsForeignLoad", true)
%w[VipsForeignLoadJpeg VipsForeignLoadPng VipsForeignLoadHeif].each { Vips.block(_1, false) }
