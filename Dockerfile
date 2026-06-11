# Summercamp WordPress — immutable image
# Parent theme (Twenty Twenty-Five) already ships inside this base image.
# Child theme + pinned plugins get baked in at the NEXT build step.
FROM wordpress:6.9-apache

# --- plugin + child-theme COPY/install steps added next build ---
