FROM continuumio/miniconda3:latest

WORKDIR /app

# Copy environment file and create conda environment
COPY environment.yml .
RUN conda env create -f environment.yml && \
    conda clean -afy

# Copy the importer script
COPY csv_importer.py .

# Set the working directory for data access
WORKDIR /data

# Activate conda environment and run script
SHELL ["conda", "run", "-n", "digital-twin", "/bin/bash", "-c"]
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "digital-twin", "python", "/app/csv_importer.py"]
CMD ["--help"]
