### 1. Punktwolken-Datenbank (Point Cloud DB)

Diese Datenbank dient der Speicherung von Metadaten und Ergebnissen, die aus der Verarbeitung von Punktwolkendaten stammen. Dies umfasst Verweise auf die Rohdaten, Segmentierungs- und Klassifikationsergebnisse.

**Zweck:** Speicherung von Roh- und verarbeiteten Punktwolkendaten sowie deren Metadaten und Analyseergebnissen, insbesondere Segmentierungs- und Klassifikationsergebnisse [379, Konversationsverlauf].

**Mermaid ER-Diagramm:**

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#ad5643',
      'primaryColor': '#5cb89c',
      'primaryTextColor': '#313d4f',
      'primaryBorderColor': '#313d4f',
      'secondaryColor': '#ad5643',
      'secondaryTextColor': '#F0F0F0',
      'secondaryBorderColor': '#ad5643',
      'tertiaryColor': '#F0F0F0',
      'tertiaryTextColor': '#000000',
      'tertiaryBorderColor': '#313d4f'
    }
  }
}%%
erDiagram
    Locations {
        INT LocationID PK "Eindeutige ID für Waldparzelle/Ort"
        VARCHAR LocationName "Name des Ortes"
        TEXT Coordinates "Geografische Koordinaten"
        TEXT Description "Beschreibung des Ortes"
    }

    PointClouds {
        INT PointCloudID PK "Eindeutige ID für Punktwolken-Scan"
        VARCHAR FilePath "Pfad/URI zur Roh-Punktwolkendatei (z.B. .las, .laz)"
        DATETIME ScanDate "Datum und Uhrzeit des Scans"
        INT LocationID FK "Referenziert Locations.LocationID"
        VARCHAR SensorType "Z.B. 'TLS', 'UAV_LiDAR'"
        VARCHAR ProcessingStatus "Aktueller Verarbeitungsstatus: 'Raw', 'Segmented', 'Classified'"
        TEXT QualityMetrics "JSON: Dichte, Genauigkeit der Punktwolke"
        DATETIME LastProcessedDate "Datum der letzten Verarbeitung"
    }

    PointCloudSegmentationResults {
        INT SegmentationResultID PK "Eindeutige ID für Segmentierungslauf"
        INT PointCloudID FK "Referenziert PointClouds.PointCloudID"
        DATETIME ProcessDate "Datum der Segmentierung"
        VARCHAR SegmentationAlgorithm "Genutzter Algorithmus (z.B. 'TreeLearn', '3D Forest')"
        TEXT SegmentDataRef "JSON: Referenzen zu individuellen Baumsegmenten (z.B. Sub-Cloud-Dateien oder IDs)"
        TEXT Metrics "JSON: Metriken zur Segmentierungsqualität"
    }

    TreeClassificationResults {
        INT ClassificationResultID PK "Eindeutige ID für Klassifikationslauf"
        INT SegmentationResultID FK "Referenziert PointCloudSegmentationResults.SegmentationResultID"
        DATETIME ProcessDate "Datum der Klassifikation"
        VARCHAR ClassificationAlgorithm "Genutzter Algorithmus (z.B. ML-Modell)"
        TEXT ClassifiedTreesData "JSON: Baum-IDs, Spezies-IDs, Wahrscheinlichkeiten, genutzte Features"
        TEXT Metrics "JSON: Klassifikationsgenauigkeit"
    }

    Locations ||--o{ PointClouds : wird_erfasst_in
    PointClouds ||--o{ PointCloudSegmentationResults : erzeugt_segm_ergebnisse
    PointCloudSegmentationResults ||--o{ TreeClassificationResults : erzeugt_klass_ergebnisse
```

**Inputs und Outputs der Punktwolken-Datenbank:**

- **Inputs:**
  - **Rohdaten:** Punktwolken, erfasst durch TLS (Terrestrial Laserscanning) oder Drohnen-LiDAR. Die Datenbank speichert typischerweise Dateipfade zu diesen großen Datensätzen.
  - **Verarbeitungsergebnisse:** Output von Algorithmen zur Segmentierung (z.B. **TreeLearn**, das individuelle Bäume aus Punktwolken segmentiert, oder **3D Forest** für Lidar-Datensegmentierung) und Klassifizierung (z.B. Speziesklassifikation mittels maschinellem Lernen). Diese Ergebnisse werden in `PointCloudSegmentationResults` und `TreeClassificationResults` gespeichert.
- **Outputs:**
  - **Baumattributsextraktion:** Segmentierte und klassifizierte Daten dienen als Input für die Ableitung quantitativer Baummetriken (Höhe, Kronenbreite, Volumen), die in die `Baumdatenbank` fließen.
  - **Strukturmodelle:** Punktwolken können als Input für die Erstellung von **Quantitative Strukturmodellen (QSMs)** mittels Tools wie **TreeQSM** dienen, deren Ergebnisse dann in die `Baumdatenbank` gelangen.
  - **Visualisierung in VR/Web:** Roh- oder verarbeitete Punktwolken können direkt für die Darstellung in XR-Anwendungen oder webbasierten Visualisierungstools genutzt werden.

---

### 2. Baumdatenbank (Tree DB)

Diese Datenbank ist das Herzstück für die Verwaltung der abgeleiteten Baumdaten und der für die VR-Darstellung sowie Wachstumsmodelle benötigten Informationen.

**Zweck:** Speicherung detaillierter Informationen über individuelle Bäume, einschließlich abgeleiteter Attribute, Strukturmodelle (QSMs, L-Systeme, DeepTree Latents) und Ergebnisse von Wachstumssimulationen [379, Konversationsverlauf].

**Mermaid ER-Diagramm:**

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#ad5643',
      'primaryColor': '#5cb89c',
      'primaryTextColor': '#313d4f',
      'primaryBorderColor': '#313d4f',
      'secondaryColor': '#ad5643',
      'secondaryTextColor': '#F0F0F0',
      'secondaryBorderColor': '#ad5643',
      'tertiaryColor': '#F0F0F0',
      'tertiaryTextColor': '#000000',
      'tertiaryBorderColor': '#313d4f'
    }
  }
}%%
erDiagram
    Locations {
        INT LocationID PK
        VARCHAR LocationName
    }

    Species {
        INT SpeciesID PK "Eindeutige ID für Baumart"
        VARCHAR CommonName "Gebräuchlicher Name"
        VARCHAR ScientificName "Wissenschaftlicher Name"
        TEXT GrowthCharacteristics "JSON: Allgemeine Wuchsformen, typische Verzweigungen"
    }

    Trees {
        INT TreeID PK "Eindeutige ID für einzelnen Baum"
        INT LocationID FK "Referenziert Locations.LocationID"
        INT SpeciesID FK "Referenziert Species.SpeciesID"
        DATETIME InitialCaptureDate "Datum der ersten Erfassung/Identifizierung des Baumes"
        FLOAT CurrentHeight_m "Aktuelle Höhe in Metern"
        FLOAT CurrentDBH_cm "Aktueller Durchmesser in Brusthöhe in cm"
        FLOAT CurrentCrownWidth_m "Aktuelle Kronenbreite in Metern"
        FLOAT CurrentVolume_m3 "Aktuelles Volumen in Kubikmetern"
        VARCHAR HealthStatus "Aktueller Gesundheitszustand"
        INT PointCloudID FK "Optional: Referenziert PointClouds.PointCloudID (für die Quell-Punktwolke)"
    }

    QuantitativeStructureModels {
        INT QSM_ID PK "Eindeutige ID für QSM"
        INT TreeID FK "Referenziert Trees.TreeID"
        VARCHAR FilePath "Pfad/URI zur QSM-Datei (.obj, .gltf, .mat, etc.)"
        DATETIME GenerationDate "Datum der QSM-Generierung"
        VARCHAR QSM_Software "Software zur QSM-Generierung (z.B. 'TreeQSM', 'rTwig')"
        TEXT QSM_Metadata "JSON: Rekonstruktionsparameter, Qualität"
    }

    TreeStructuralRepresentations {
        INT StructuralRepID PK "Eindeutige ID für Strukturdarstellung"
        INT TreeID FK "Referenziert Trees.TreeID"
        VARCHAR RepresentationType "Typ der Darstellung (z.B. 'LSystemString', 'DeepTreeLatent')"
        TEXT RepresentationData "Die eigentliche Daten (z.B. L-System String, DeepTree Latent Vector)"
        DATETIME DataGenerationDate "Datum der Generierung dieser Darstellung"
        TEXT GrowthModelContext "JSON: Alter, Gravitropismus-Parameter, falls generiert"
    }

    TreeGrowthSimulations {
        INT SimulationID PK "Eindeutige ID für Wachstumssimulation"
        INT TreeID FK "Referenziert Trees.TreeID"
        VARCHAR ModelType "Genutztes Wachstumsmodell (z.B. 'SILVA', 'BALANCE', 'DeepTree')"
        DATETIME SimulationTimestamp "Zeitpunkt der Simulation"
        FLOAT PredictedHeight_m "Prognostizierte Höhe"
        FLOAT PredictedDBH_cm "Prognostizierter DBH"
        FLOAT PredictedVolume_m3 "Prognostiziertes Volumen"
        FLOAT MortalityRisk_prob "Prognostiziertes Sterberisiko"
        TEXT PredictedLSystemString "Optional: Prognostizierter L-System String, falls Modell-Output"
        TEXT PredictedDeepTreeLatent "Optional: Prognostizierter DeepTree Latent, falls Modell-Output"
        INT EnvironmentalSnapshotID FK "Referenziert EnvironmentalSnapshots.SnapshotID (aus Environment DB)"
    }

    Locations ||--o{ Trees : beinhaltet
    Species ||--o{ Trees : hat_art
    Trees ||--o{ QuantitativeStructureModels : hat_QSM
    Trees ||--o{ TreeStructuralRepresentations : hat_struktur_rep
    Trees ||--o{ TreeGrowthSimulations : hat_wachstums_sim
```

**Inputs und Outputs der Baumdatenbank:**

- **Inputs:**
  - **Baumattributsextraktion:** Quantitative Metriken (Höhe, Kronenbreite, Volumen) extrahiert aus Punktwolken werden in `Trees` aktualisiert.
  - **Forstinventur:** Traditionelle Messdaten (DBH, Höhe) dienen als Initialwerte oder zur Validierung in `Trees`.
  - **Quantitative Strukturmodelle (QSMs):** Modelle, die aus Punktwolken mittels **TreeQSM** oder **rTwig** erstellt wurden, werden in `QuantitativeStructureModels` gespeichert oder referenziert. `rTwig` verbessert die visuelle Realität und Volumenakkuratheit von QSMs.
  - **Baumwachstumsmodelle:** Ergebnisse von Modellen wie **SILVA** und **BALANCE** werden in `TreeGrowthSimulations` erfasst. Diese Modelle benötigen Baumdimensionen, Spezies, Standort- und Klimadaten als Input.
  - **Generative Modelle (L-Systeme/DeepTree):** `L-Systeme` als string-rewriting Systeme oder `DeepTree` als Deep-Learning-Modell, das Wachstumsregeln lernt, können Strukturdaten generieren, die in `TreeStructuralRepresentations` gespeichert werden. `Latent L-systems` ersetzen die manuelle Regelerstellung durch ein Transformer-Modell. `DeepTree` lernt aus dem "situated latent space" und kann Umwelteinflüsse kodieren.
  - **Nutzerinteraktion:** Werkzeuge zur Interaktion können Daten in `Trees` und `TreeGrowthSimulations` anpassen oder Szenarien simulieren.
- **Outputs:**
  - **VR-Darstellung:** Die `Trees`-Tabelle sowie `QuantitativeStructureModels` und `TreeStructuralRepresentations` liefern die notwendigen geometrischen und topologischen Informationen für die realitätsnahe Darstellung von Bäumen in VR als "Virtual Tree Model".
  - **Input für Wachstumsmodelle:** Die aktuellen Baumdaten aus `Trees` und `TreeStructuralRepresentations` dienen als Input für wiederkehrende Simulationen mit **SILVA**, **BALANCE** oder **DeepTree**.
  - **Szenarienanalyse:** Die kombinierten Daten können für Hypothesentests und die Simulation von Management-Szenarien genutzt werden.

---

### 3. Umgebungsdatenbank (Environment DB)

Diese Datenbank konzentriert sich auf die Erfassung und Verwaltung von Umweltdaten, die für die Baumwachstumsmodelle und die VR-Umgebungssimulation unerlässlich sind.

**Zweck:** Integration von Sensordaten und Umweltdaten (Klima, Wetter, Boden, Grundwasser) zur Unterstützung von Wachstumsmodellen und zur Simulation der Umgebung in VR [379, Konversationsverlauf].

**Mermaid ER-Diagramm:**

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#ad5643',
      'primaryColor': '#5cb89c',
      'primaryTextColor': '#313d4f',
      'primaryBorderColor': '#313d4f',
      'secondaryColor': '#ad5643',
      'secondaryTextColor': '#F0F0F0',
      'secondaryBorderColor': '#ad5643',
      'tertiaryColor': '#F0F0F0',
      'tertiaryTextColor': '#000000',
      'tertiaryBorderColor': '#313d4f'
    }
  }
}%%
erDiagram
    Locations {
        INT LocationID PK
        VARCHAR LocationName
    }

    Sensors {
        INT SensorID PK "Eindeutige ID für Sensor"
        INT LocationID FK "Referenziert Locations.LocationID"
        VARCHAR SensorType "Typ des Sensors (z.B. 'EcoSense', 'WeatherStation')"
        DATETIME InstallationDate "Installationsdatum"
        VARCHAR Status "Status des Sensors"
        TEXT SensorConfig "JSON: Konfiguration und Kalibrierungsdaten"
    }

    SensorReadings {
        INT ReadingID PK "Eindeutige ID für Messwert"
        INT SensorID FK "Referenziert Sensors.SensorID"
        DATETIME Timestamp "Zeitstempel der Messung"
        VARCHAR ReadingType "Art der Messung (z.B. 'Temperature', 'LightIntensity', 'SapFlow')"
        FLOAT Value "Messwert"
        VARCHAR Unit "Einheit des Messwerts"
    }

    EnvironmentalSnapshots {
        INT SnapshotID PK "Eindeutige ID für Umweltschnappschuss"
        INT LocationID FK "Referenziert Locations.LocationID"
        DATETIME Timestamp "Zeitstempel des Schnappschusses (aggregiert)"
        FLOAT AvgTemperature_C "Durchschnittstemperatur"
        FLOAT AvgHumidity_percent "Durchschnittliche Luftfeuchtigkeit"
        FLOAT TotalPrecipitation_mm "Gesamtniederschlag"
        FLOAT AvgGlobalRadiation "Durchschnittliche Globalstrahlung"
        FLOAT AvgCO2_ppm "Durchschnittlicher CO2-Gehalt"
        FLOAT AvgWindSpeed_ms "Durchschnittliche Windgeschwindigkeit"
        FLOAT DominantWindDirection_deg "Dominante Windrichtung"
        TEXT ObstacleVoxelGridRef "Pfad/URI zu externen Hindernis-Voxel-Grids (z.B. für DeepTree)"
        TEXT OtherEnvironmentalFactors "JSON: Bodenfeuchte, Bodennährstoffe, Grundwasserspiegel, Schadstoffe"
    }

    Locations ||--o{ Sensors : hat_sensoren
    Sensors ||--o{ SensorReadings : sammelt_daten
    Locations ||--o{ EnvironmentalSnapshots : hat_umwelt_snapshots
    EnvironmentalSnapshots }o--|| SensorReadings : aggregiert_aus
```

**Inputs und Outputs der Umgebungsdatenbank:**

- **Inputs:**
  - **Sensordaten:** Daten von **EcoSense-Sensoren** und anderen Quellen (Klima-, Wetter-, Boden-, Grundwasserdaten) werden in `SensorReadings` erfasst und in `EnvironmentalSnapshots` aggregiert.
  - **Umweltmodelle:** Ergebnisse von Umweltmodellen oder externe Datensätze (z.B. präzise Schadstoffdaten, die in `OtherEnvironmentalFactors` abgelegt werden können).
  - **Nutzerinteraktion:** Nutzer können Umweltdaten manuell anpassen, um Szenarien zu testen (z.B. Klimaszenarien für Wachstumsmodelle).
- **Outputs:**
  - **Wachstumsmodelle:** Die aggregierten Umweltschnappschüsse (`EnvironmentalSnapshots`) dienen als essentielle Input-Parameter für baum- und waldwachstumsmodelle wie **SILVA** und **BALANCE**, da diese Modelle die Reaktion der Bäume auf ihre Umgebung berücksichtigen.
  - **VR-Umgebungssimulation:** Die Umgebungsdaten sind entscheidend für die realitätsnahe Simulation der Waldumgebung in VR ("Environment Simulation") und die Visualisierung von Sensordaten in Echtzeit ("Sensor Data Visualization").

---

### Zusätzliche Überlegungen zur VR-Darstellung und Schnittstellen

Ihre Hauptaufgabe, die Informationen aus der Baumdatenbank für eine möglichst realitätsnahe VR-Darstellung aufzubereiten, wird durch dieses Design stark unterstützt:

- **Strukturmodelle (QSMs, L-Systeme, DeepTree):** Die explizite Speicherung dieser Modelle in `QuantitativeStructureModels` und `TreeStructuralRepresentations` ist entscheidend.
  - **QSMs** bieten eine hervorragende Grundlage, da sie die Holzstruktur realer Bäume als hierarchische Zylindersammlungen repräsentieren und detaillierte Geometrie liefern. Tools wie **TreeQSM** und **rTwig** ermöglichen die Rekonstruktion direkt aus Scandaten. Der `FilePath` in `QuantitativeStructureModels` würde direkt auf die exportierten 3D-Modellformate wie OBJ oder GLTF verweisen, die direkt in VR-Engines geladen werden können.
  - **L-Systeme** und **DeepTree** können als komplementäre Methoden eingesetzt werden, um die Bäume prozedural zu generieren oder zu vervollständigen, insbesondere wenn Scandaten unvollständig sind oder für die Erzeugung neuer Bäume, die gelernten Wachstumsformen folgen. Die `RepresentationData` (z.B. der L-String oder der Latent-Vektor) in `TreeStructuralRepresentations` dient als "Saat" für die Generierung des 3D-Modells in der VR-Anwendung.
- **Dynamische Anpassung in VR:** Durch die Verknüpfung von `TreeGrowthSimulations` mit `EnvironmentalSnapshots` können VR-Anwendungen nicht nur statische Bäume darstellen, sondern auch deren simuliertes Wachstum und ihre Reaktion auf Umwelteinflüsse über die Zeit visualisieren ("Temporal Dynamics").
- **Validierung:** Die in den Quellen genannten Validierungsmethoden (geometrische Vergleiche, perzeptuelle Metriken wie **ICTree**) sind essenziell, um die Realitätsnähe der generierten und dargestellten Bäume zu gewährleisten. Die `TreeDB` mit ihren Attributen und den `QuantitativeStructureModels` bietet die Datenbasis für solche Validierungen.

Diese Datenbankstruktur schafft eine robuste Grundlage für Ihr Projekt und ermöglicht eine effiziente Verwaltung und Integration der komplexen Baum- und Umweltdaten für Ihre VR-Anwendungen und Wachstumsmodelle.
