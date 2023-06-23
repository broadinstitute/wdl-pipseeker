version 1.0

workflow pipseeker {
  input {
    String sample_name
    File R1_fastq
    File R2_fastq
    File STAR_index_tgz
    String gs_output_subdir
  }

  call run_pipseeker {
    input:
    sample_name=sample_name,
    R1_fastq=R1_fastq,
    R2_fastq=R2_fastq,
    STAR_index_tgz=STAR_index_tgz
  }

  call copy_to_bucket {
    input:
    gs_output_subdir=gs_output_subdir,
    input_tgz=run_pipseeker.out_tgz
  }

  output {
    String pipseeker_ouput = gs_output_subdir
    File monitoring = run_pipseeker.monitoring
  }
}

task run_pipseeker {
  input {
    String sample_name
    File R1_fastq
    File R2_fastq
    File STAR_index_tgz
  }

  Float input_files_gb = size(R1_fastq, "GB") + size(R2_fastq, "GB")
  Int memory_size = 2 * input_files_gb + 10
  Int disk_size = 10 * input_files_gb + 32

  command {
  set -e

  # set up monitoring
  curl -O https://raw.githubusercontent.com/lilab-bcb/cumulus/master/docker/monitor_script.sh
  monitor_script.sh > monitoring.log &
  
  # extract index
  mkdir -p genome_dir
  tar xf ~{STAR_index_tgz} -C genome_dir --strip-components 1

  /home/pipseeker full --fastq $(dirname ~{R1_fastq})/sample_name --star-index-path genome_dir --output-path output --chemistry v4

  tar -czf output.tgz output/
  }

  output {
    File out_tgz="output.tgz"
    File monitoring = "monitorying.log"
  }

  runtime {
    container: "public.ecr.aws/w3e1n2j6/fluent-pipseeker:latest"
    cpu: 8
    memory: memory_size + "G"
    disks: "local-disk ~{disk_size} HDD"
    }    
}

task copy_to_bucket {
  input {
    String gs_output_subdir
    File input_tgz
  }

  Float input_files_gb = size(input_tgz, "GB")
  Int disk_size = 3 * input_files_gb + 32
  
  command {
  tar -xzf ~{input_tgz}
  gsutil cp -r output/* ~{gs_output_subdir}
  }

  runtime {
    docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:latest"
    disks: "local-disk ~{disk_size} HDD"
  }
}
