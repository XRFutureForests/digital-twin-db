#!/usr/bin/env Rscript
#' Digital Forest Twin - Interactive Tree Data Importer (R)
#' Connects to database, introspects schema, loads CSV, and applies user-defined mapping.

library(RPostgres)
library(DBI)
library(readr)
library(dplyr)
library(jsonlite)
library(dotenv)
library(R6)

# Load environment variables
env_file <- "../../docker/.env"
if (file.exists(env_file)) {
  load_dot_env(env_file)
}

TreeImporter <- R6::R6Class(
  "TreeImporter",
  public = list(
    db_connection = NULL,
    postgres_host = NULL,
    postgres_user = NULL,
    postgres_password = NULL,
    postgres_database = NULL,
    reference_data = NULL,

    initialize = function(postgres_host = "localhost",
                         postgres_user = "postgres",
                         postgres_password = NULL,
                         postgres_database = "postgres",
                         postgres_port = 5432) {
      self$postgres_host <- postgres_host
      self$postgres_user <- postgres_user
      self$postgres_password <- postgres_password
      self$postgres_database <- postgres_database
      self$postgres_port <- postgres_port
      self$reference_data <- list()

      if (is.null(postgres_password)) {
        cat("❌ POSTGRES_PASSWORD not set in environment variables\n")
      } else {
        self$connect()
      }
    },

    connect = function() {
      "Connect to PostgreSQL database"
      tryCatch({
        self$db_connection <- dbConnect(
          RPostgres::Postgres(),
          host = self$postgres_host,
          user = self$postgres_user,
          password = self$postgres_password,
          dbname = self$postgres_database,
          port = self$postgres_port
        )
        cat("✓ Connected to PostgreSQL database\n")
      }, error = function(e) {
        cat(sprintf("❌ Database connection failed: %s\n", e$message))
      })
    },

    disconnect = function() {
      "Close database connection"
      if (!is.null(self$db_connection)) {
        dbDisconnect(self$db_connection)
        self$db_connection <- NULL
      }
    }

    introspect_database = function() {
      "
      Query database to get all tables and columns in custom schemas.
      Returns: list(schema_name = list(table_name = c(column1, column2, ...)))
      "
      cat("\n🔍 Introspecting database schema...\n")

      if (is.null(self$db_connection)) {
        cat("❌ Not connected to database, using hardcoded schema\n")
        return(self$get_hardcoded_schema())
      }

      tryCatch({
        # Query information_schema for all tables and columns
        query <- "
          SELECT
            table_schema,
            table_name,
            column_name
          FROM information_schema.columns
          WHERE table_schema IN ('shared', 'trees', 'sensor', 'pointclouds', 'environments')
          ORDER BY table_schema, table_name, ordinal_position
        "
        result <- dbGetQuery(self$db_connection, query)

        # Build nested list structure
        schema_info <- list()
        for (i in seq_len(nrow(result))) {
          schema <- result$table_schema[i]
          table <- result$table_name[i]
          column <- result$column_name[i]

          if (!(schema %in% names(schema_info))) {
            schema_info[[schema]] <- list()
          }
          if (!(table %in% names(schema_info[[schema]]))) {
            schema_info[[schema]][[table]] <- c()
          }

          schema_info[[schema]][[table]] <- c(schema_info[[schema]][[table]], column)
        }

        cat("✓ Found ", length(unlist(schema_info)), " columns across ", length(schema_info), " schemas\n")
        return(schema_info)
      }, error = function(e) {
        cat(sprintf("⚠ Schema introspection failed: %s\n", e$message))
        cat("Using hardcoded schema as fallback\n")
        return(self$get_hardcoded_schema())
      })
    },

    get_hardcoded_schema = function() {
      "Hardcoded schema as fallback (or use RPostgres for live query)"
      list(
        trees = list(
          Trees = c(
            "VariantID", "LocationID", "SpeciesID", "Height_m", "Volume_m3",
            "Position", "PositionOriginal", "FieldNotes", "CreatedBy", "CreatedAt"
          ),
          Stems = c("StemID", "TreeID", "StemNumber", "Diameter_m", "CreatedBy")
        ),
        sensor = list(
          Sensors = c(
            "SensorID", "LocationID", "SensorTypeID", "SerialNumber",
            "Position", "PositionOriginal", "InstallationDate", "CreatedBy"
          ),
          SensorReadings = c(
            "ReadingID", "SensorID", "Timestamp", "Value", "Quality", "CreatedAt"
          )
        ),
        shared = list(
          Species = c("SpeciesID", "CommonName", "ScientificName"),
          Locations = c("LocationID", "LocationName", "CenterPoint")
        )
      )
    },

    load_reference_data = function() {
      "Load reference data (Species, Locations, SensorTypes) for mapping help"
      if (is.null(self$db_connection)) {
        cat("⚠ Not connected to database, skipping reference data\n")
        return()
      }

      tryCatch({
        # Load Species
        species_query <- "SELECT SpeciesID, CommonName, ScientificName FROM shared.Species ORDER BY CommonName"
        species_df <- dbGetQuery(self$db_connection, species_query)
        self$reference_data[["Species"]] <- species_df

        # Load Locations
        locations_query <- "SELECT LocationID, LocationName FROM shared.Locations ORDER BY LocationName"
        locations_df <- dbGetQuery(self$db_connection, locations_query)
        self$reference_data[["Locations"]] <- locations_df

        # Load SensorTypes (if exists)
        tryCatch({
          sensor_types_query <- "SELECT SensorTypeID, SensorTypeName FROM sensor.SensorTypes ORDER BY SensorTypeName"
          sensor_types_df <- dbGetQuery(self$db_connection, sensor_types_query)
          self$reference_data[["SensorTypes"]] <- sensor_types_df
        }, error = function(e) {
          # Silently skip if SensorTypes doesn't exist
        })

        cat("✓ Reference data loaded\n")
      }, error = function(e) {
        cat(sprintf("⚠ Failed to load reference data: %s\n", e$message))
      })
    },

    display_reference_data = function() {
      "Display reference data tables for mapping guidance"
      if (length(self$reference_data) == 0) {
        return()
      }

      cat("\n", strrep("=", 80), "\n")
      cat("📚 REFERENCE DATA - Use these for mapping CSV values to database IDs\n")
      cat(strrep("=", 80), "\n")

      if (!is.null(self$reference_data[["Species"]])) {
        cat("\n📚 Species:\n")
        print(self$reference_data[["Species"]])
      }

      if (!is.null(self$reference_data[["Locations"]])) {
        cat("\n📚 Locations:\n")
        print(self$reference_data[["Locations"]])
      }

      if (!is.null(self$reference_data[["SensorTypes"]])) {
        cat("\n📚 SensorTypes:\n")
        print(self$reference_data[["SensorTypes"]])
      }
    },

    display_schema = function(schema_info) {
      "Display available database tables and columns"
      cat("\n", strrep("=", 80), "\n")
      cat("DATABASE SCHEMA - Available Tables & Columns\n")
      cat(strrep("=", 80), "\n")

      for (schema_name in names(schema_info)) {
        cat(sprintf("\n📦 Schema: %s\n", schema_name))

        tables <- schema_info[[schema_name]]
        for (table_name in names(tables)) {
          columns <- tables[[table_name]]
          cat(sprintf("  📋 %s (%d columns)\n", table_name, length(columns)))

          for (i in seq_along(columns)) {
            cat(sprintf("     %2d. %s\n", i, columns[i]))
          }
        }
      }
    },

    load_csv = function(csv_path) {
      "Load and display CSV file"
      df <- read_csv(csv_path, show_col_types = FALSE)

      cat(sprintf("\n📄 CSV File: %s\n", basename(csv_path)))
      cat(sprintf("   Rows: %d\n", nrow(df)))
      cat(sprintf("   Columns: %s\n", paste(names(df), collapse = ", ")))
      cat("\nFirst 3 rows:\n")
      print(head(df, 3))

      return(df)
    },

    show_column_samples = function(df, column_name, num_samples = 5) {
      "Show sample values from CSV column to help with LOOKUP"
      unique_values <- unique(df[[column_name]])
      num_to_show <- min(num_samples, length(unique_values))
      cat(sprintf("  Sample values from '%s':\n", column_name))
      for (val in unique_values[1:num_to_show]) {
        cat(sprintf("    - %s\n", val))
      }
      if (length(unique_values) > num_to_show) {
        cat(sprintf("    ... and %d more unique values\n", length(unique_values) - num_to_show))
      }
    },

    interactive_mapping = function(csv_columns, schema_info, df = NULL) {
      "
      Interactive mapping creation with LOOKUP support.
      Returns: list(csv_column = list(schema = schema_name, table = table_name, column = column_name, special = format))
      "
      mapping <- list()

      cat("\n", strrep("=", 80), "\n")
      cat("COLUMN MAPPING - Map each CSV column to database table & column\n")
      cat(strrep("=", 80), "\n")
      cat("Format: schema.table.column (e.g., trees.Trees.Height_m)\n")
      cat("Or: LOOKUP to see CSV values before mapping\n")
      cat("Or: SKIP to ignore this column\n")
      cat("Or: lat_lon:EPSG:4326 / x_y:EPSG:32632 for coordinates\n")
      cat(strrep("=", 80), "\n")

      for (csv_col in csv_columns) {
        repeat {
          cat(sprintf("\n'%s' maps to: ", csv_col))
          target <- readline()
          target <- trimws(target)

          if (tolower(target) == "skip") {
            mapping[[csv_col]] <- NULL
            break
          }

          if (tolower(target) == "lookup") {
            if (is.null(df)) {
              cat("   ⚠ No CSV data available for lookup\n")
              next
            }
            self$show_column_samples(df, csv_col)
            next
          }

          # Handle coordinate mappings (lat_lon:EPSG:4326 or x_y:EPSG:32632)
          if (grepl("^(lat_lon|x_y):", target, ignore.case = TRUE)) {
            mapping[[csv_col]] <- list(
              special = target,
              column = csv_col
            )
            cat(sprintf("   ✓ Mapped to coordinate transform: %s\n", target))
            break
          }

          parts <- strsplit(target, "\\.")[[1]]
          if (length(parts) == 3) {
            schema <- parts[1]
            table <- parts[2]
            column <- parts[3]

            # Validate
            if (schema %in% names(schema_info) &&
              table %in% names(schema_info[[schema]]) &&
              column %in% schema_info[[schema]][[table]]) {

              mapping[[csv_col]] <- list(
                schema = schema,
                table = table,
                column = column
              )
              cat(sprintf("   ✓ Mapped to %s.%s.%s\n", schema, table, column))
              break
            } else {
              cat(sprintf("   ❌ Invalid: %s.%s.%s not found\n", schema, table, column))
              available_schemas <- paste(names(schema_info)[1:min(3, length(schema_info))], collapse = ", ")
              cat(sprintf("   Try one of: %s.table.column\n", available_schemas))
            }
          } else {
            cat("   ❌ Use format: schema.table.column\n")
          }
        }
      }

      return(mapping)
    },

    save_mapping = function(mapping, output_path) {
      "Save mapping as JSON for reuse"
      mapping_json <- toJSON(mapping, pretty = TRUE)
      write(mapping_json, file = output_path)
      cat(sprintf("\n✓ Mapping saved to %s\n", output_path))
    },

    load_mapping = function(mapping_path) {
      "Load previously saved mapping"
      mapping_json <- read_file(mapping_path)
      mapping <- fromJSON(mapping_json)
      return(mapping)
    },

    detect_coordinate_columns = function(df, format_spec) {
      "Detect latitude/longitude or x/y columns based on flexible naming"
      col_names <- tolower(names(df))

      if (grepl("^lat_lon", format_spec, ignore.case = TRUE)) {
        # Find latitude column
        lat_patterns <- c("latitude", "lat", "gps_latitude", "gps_lat", "y")
        lat_col <- NULL
        for (pattern in lat_patterns) {
          matching <- grep(pattern, col_names, fixed = TRUE)
          if (length(matching) > 0) {
            lat_col <- names(df)[matching[1]]
            break
          }
        }

        # Find longitude column
        lon_patterns <- c("longitude", "lon", "gps_longitude", "gps_lon", "x")
        lon_col <- NULL
        for (pattern in lon_patterns) {
          matching <- grep(pattern, col_names, fixed = TRUE)
          if (length(matching) > 0) {
            lon_col <- names(df)[matching[1]]
            break
          }
        }

        list(lat = lat_col, lon = lon_col)
      } else if (grepl("^x_y", format_spec, ignore.case = TRUE)) {
        # Find x/easting column
        x_patterns <- c("x", "easting", "utm_x", "x_32632", "x_32633", "easting_m")
        x_col <- NULL
        for (pattern in x_patterns) {
          matching <- grep(pattern, col_names, fixed = TRUE)
          if (length(matching) > 0) {
            x_col <- names(df)[matching[1]]
            break
          }
        }

        # Find y/northing column
        y_patterns <- c("y", "northing", "utm_y", "y_32632", "y_32633", "northing_m")
        y_col <- NULL
        for (pattern in y_patterns) {
          matching <- grep(pattern, col_names, fixed = TRUE)
          if (length(matching) > 0) {
            y_col <- names(df)[matching[1]]
            break
          }
        }

        list(x = x_col, y = y_col)
      }
    },

    create_wkt_point = function(lon, lat) {
      "Create WKT POINT geometry from coordinates"
      sprintf("POINT(%f %f)", lon, lat)
    },

    apply_coordinate_mapping = function(df, mapping) {
      "Process coordinate columns and create POINT geometry"
      coord_mappings <- list()

      for (csv_col in names(mapping)) {
        target <- mapping[[csv_col]]

        if (is.null(target) || is.null(target$special)) {
          next
        }

        if (grepl("^(lat_lon|x_y):", target$special, ignore.case = TRUE)) {
          coord_mappings[[csv_col]] <- target$special
        }
      }

      if (length(coord_mappings) == 0) {
        return(df)
      }

      cat("\n🔄 Processing coordinate columns...\n")

      for (csv_col in names(coord_mappings)) {
        format_spec <- coord_mappings[[csv_col]]

        # Extract CRS if provided
        crs_match <- regmatches(format_spec, regexpr("EPSG:[0-9]+", format_spec))
        source_crs <- if (length(crs_match) > 0) crs_match[1] else NA

        coords <- self$detect_coordinate_columns(df, format_spec)

        if (grepl("^lat_lon", format_spec, ignore.case = TRUE)) {
          if (is.null(coords$lat) || is.null(coords$lon)) {
            cat(sprintf("   ⚠ Could not find latitude/longitude columns for '%s'\n", csv_col))
            next
          }

          cat(sprintf("   Processing: %s (lat: %s, lon: %s, CRS: %s)\n",
                     csv_col, coords$lat, coords$lon, source_crs))

          # Create WKT POINT geometry
          points <- vector("character", nrow(df))
          for (i in seq_len(nrow(df))) {
            lon <- as.numeric(df[[coords$lon]][i])
            lat <- as.numeric(df[[coords$lat]][i])

            # Validate coordinates
            if (!is.na(lon) && !is.na(lat) &&
                lat >= -90 && lat <= 90 &&
                lon >= -180 && lon <= 180) {
              points[i] <- self$create_wkt_point(lon, lat)
            } else {
              points[i] <- NA_character_
            }
          }

          df[["Position"]] <- points
          cat(sprintf("   ✓ Created Position column with %d valid geometries\n", sum(!is.na(points))))

        } else if (grepl("^x_y", format_spec, ignore.case = TRUE)) {
          if (is.null(coords$x) || is.null(coords$y)) {
            cat(sprintf("   ⚠ Could not find x/y columns for '%s'\n", csv_col))
            next
          }

          cat(sprintf("   Processing: %s (x: %s, y: %s, CRS: %s)\n",
                     csv_col, coords$x, coords$y, source_crs))

          # Transform to WGS84 if needed
          # Note: R version requires sf package for full transformation
          # For now, just create points as-is with note to user
          if (!is.na(source_crs) && source_crs != "EPSG:4326") {
            cat(sprintf("   ℹ Note: CRS transformation from %s to EPSG:4326 requires sf package\n", source_crs))
            cat("   Install with: install.packages('sf')\n")
          }

          points <- vector("character", nrow(df))
          for (i in seq_len(nrow(df))) {
            x <- as.numeric(df[[coords$x]][i])
            y <- as.numeric(df[[coords$y]][i])

            if (!is.na(x) && !is.na(y)) {
              # For UTM coordinates, assume order is x (easting) then y (northing)
              points[i] <- sprintf("POINT(%f %f)", x, y)
            } else {
              points[i] <- NA_character_
            }
          }

          df[["Position"]] <- points
          cat(sprintf("   ✓ Created Position column with %d valid geometries\n", sum(!is.na(points))))
        }
      }

      return(df)
    },

    apply_mapping = function(df, mapping) {
      "
      Apply mapping to create data frames per table.
      Returns: list(full_table_name = data frame)
      "
      table_dfs <- list()

      for (csv_col in names(mapping)) {
        target <- mapping[[csv_col]]

        if (is.null(target)) {
          next
        }

        # Skip coordinate mappings as they create Position column directly
        if (!is.null(target$special)) {
          next
        }

        table_key <- sprintf("%s.%s", target$schema, target$table)
        column_name <- target$column

        if (!(table_key %in% names(table_dfs))) {
          table_dfs[[table_key]] <- tibble()
        }

        # Add column to table dataframe
        table_dfs[[table_key]][[column_name]] <- df[[csv_col]]
      }

      # Handle Position column if it exists
      if ("Position" %in% names(df)) {
        # Find which table should get the Position column
        # Default to trees.Trees if it exists
        if ("trees.Trees" %in% names(table_dfs)) {
          table_dfs[["trees.Trees"]][["Position"]] <- df[["Position"]]
        } else if ("sensor.Sensors" %in% names(table_dfs)) {
          table_dfs[["sensor.Sensors"]][["Position"]] <- df[["Position"]]
        } else if (length(table_dfs) > 0) {
          # Add to first table if available
          first_table <- names(table_dfs)[1]
          table_dfs[[first_table]][["Position"]] <- df[["Position"]]
        }
      }

      return(table_dfs)
    },

    preview_mapped_data = function(table_dfs) {
      "Preview how data will be inserted"
      cat("\n", strrep("=", 80), "\n")
      cat("DATA PREVIEW - How data will be inserted into each table\n")
      cat(strrep("=", 80), "\n")

      for (table_name in names(table_dfs)) {
        df <- table_dfs[[table_name]]
        cat(sprintf("\n📊 %s (%d rows, %d columns)\n", table_name, nrow(df), ncol(df)))
        cat(sprintf("   Columns: %s\n", paste(names(df), collapse = ", ")))
        cat("\n   First 2 rows:\n")
        print(head(df, 2))
      }
    }
  )
)

# Main workflow
main <- function() {
  # Load environment
  postgres_password <- Sys.getenv("POSTGRES_PASSWORD")

  if (postgres_password == "") {
    cat("❌ POSTGRES_PASSWORD not found in docker/.env\n")
    return()
  }

  # Initialize importer
  importer <- TreeImporter$new(
    postgres_host = "localhost",
    postgres_user = "postgres",
    postgres_password = postgres_password,
    postgres_database = "postgres",
    postgres_port = 5432
  )

  # Step 1: Introspect database
  cat("\n", strrep("=", 80), "\n")
  cat("🌳 DIGITAL FOREST TWIN - Data Importer\n")
  cat(strrep("=", 80), "\n")

  schema_info <- importer$introspect_database()

  # Step 2: Display schema
  importer$display_schema(schema_info)

  # Step 3: Load CSV
  csv_path <- "../../data/mathisle_250904.csv"
  if (!file.exists(csv_path)) {
    cat("\nEnter path to CSV file: ")
    csv_path <- readline()
  }

  if (!file.exists(csv_path)) {
    cat(sprintf("❌ CSV file not found: %s\n", csv_path))
    return()
  }

  df <- importer$load_csv(csv_path)

  # Step 4: Load reference data
  importer$load_reference_data()
  importer$display_reference_data()

  # Step 5: Show coordinate mapping help
  cat("\n", strrep("=", 80), "\n")
  cat("📍 COORDINATE MAPPING - If your CSV has lat/lon or x/y columns\n")
  cat(strrep("=", 80), "\n")
  cat("When mapping coordinates, use these formats:\n\n")
  cat("  Option 1 - Latitude/Longitude (WGS84):\n")
  cat("    Format: lat_lon:EPSG:4326\n")
  cat("    Example: gps_data -> lat_lon:EPSG:4326\n")
  cat("    (Script auto-detects lat/lon columns)\n\n")
  cat("  Option 2 - UTM or other projected CRS:\n")
  cat("    Format: x_y:EPSG:32632\n")
  cat("    Example: utm_data -> x_y:EPSG:32632\n")
  cat("    (Script auto-detects x/y columns)\n\n")
  cat("  Option 3 - Skip coordinates:\n")
  cat("    Just map other columns and skip coordinate columns\n")
  cat(strrep("=", 80), "\n")

  # Step 6: Create mapping
  mapping <- importer$interactive_mapping(names(df), schema_info, df)

  # Step 7: Save mapping
  mapping_path <- sprintf("%s_%s", tools::file_path_sans_ext(csv_path), "mapping.json")
  importer$save_mapping(mapping, mapping_path)

  # Step 8: Apply coordinate mapping
  cat("\n🔄 Processing columns...\n")
  df <- importer$apply_coordinate_mapping(df, mapping)

  # Step 9: Apply column mapping and preview
  table_dfs <- importer$apply_mapping(df, mapping)
  importer$preview_mapped_data(table_dfs)

  # Step 10: Next steps
  cat("\n", strrep("=", 80), "\n")
  cat("Next Steps:\n")
  cat(strrep("=", 80), "\n")
  cat("1. Review the preview above\n")
  cat("2. Mapping saved to:", mapping_path, "\n")
  cat("3. Data is ready in data frames for insertion\n")
  cat("4. Insert using:\n")
  cat("   for (table_name in names(table_dfs)) {\n")
  cat("     df <- table_dfs[[table_name]]\n")
  cat("     # Use RPostgres or httr to insert\n")
  cat("   }\n")
  cat(strrep("=", 80), "\n")

  # Cleanup
  importer$disconnect()
}

# Run main
if (!interactive()) {
  main()
}
