FROM continuumio/miniconda3:latest

WORKDIR /app

# Copy environment file and create conda environment
COPY environment.yaml .
RUN conda env create -f environment.yaml && \
    conda clean -afy

# Copy the importer script
COPY csv_importer.py .

# Set the working directory for data access
WORKDIR /data

# Activate conda environment and run script
SHELL ["conda", "run", "-n", "dftdb-import", "/bin/bash", "-c"]
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "dftdb-import", "python", "/app/csv_importer.py"]
CMD ["--help"]
