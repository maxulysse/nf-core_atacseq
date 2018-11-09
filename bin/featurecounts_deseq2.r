#!/usr/bin/env Rscript

################################################
################################################
## REQUIREMENTS                               ##
################################################
################################################

## DIFFERENTIAL ANALYSIS, SCATTERPLOTS AND PCA FOR SAMPLES IN FEATURECOUNTS FILE
		## - FIRST SIX COLUMNS OF FEATURECOUNTS_FILE SHOULD BE INTERVAL INFO. REMAINDER OF COLUMNS SHOULD BE SAMPLES-SPECIFIC COUNTS.
		## - SAMPLE NAMES HAVE TO END IN "_R1" REPRESENTING REPLICATE ID. LAST 3 CHARACTERS OF SAMPLE NAME WILL BE TRIMMED TO OBTAIN GROUP ID FOR DESEQ2 COMPARISONS.
		## - BAM_SUFFIX IS PORTION OF FILENAME AFTER SAMPLE NAME IN FEATURECOUNTS COLUMN SAMPLE NAMES E.G. ".rmDup.bam" if "DRUG_R1.rmDup.bam"
		## - PACKAGES BELOW NEED TO BE AVAILABLE TO LOAD WHEN RUNNING R

################################################
################################################
## LOAD LIBRARIES                             ##
################################################
################################################

library(optparse)
library(DESeq2)
library(vsn)
library(ggplot2)
library(RColorBrewer)
library(pheatmap)
library(lattice)

################################################
################################################
## PARSE COMMAND-LINE PARAMETERS              ##
################################################
################################################

option_list <- list(make_option(c("-i", "--featurecount_file"), type="character", default=NULL, help="Feature count file generated by the SubRead featureCounts command.", metavar="featurecount_file"),
                    make_option(c("-b", "--bam_suffix"), type="character", default=NULL, help="Portion of filename after sample name in featurecount file header e.g. '.rmDup.bam' if 'DRUG_R1.rmDup.bam'", metavar="bam_suffix"),
                    make_option(c("-o", "--outdir"), type="character", default='./', help="Output directory", metavar="path"),
                    make_option(c("-p", "--outprefix"), type="character", default='differential', help="Output prefix", metavar="character"),
                    make_option(c("-s", "--outsuffix"), type="character", default='', help="Output suffix for comparison-level results", metavar="character"))

opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

if (is.null(opt$featurecount_file)){
    print_help(opt_parser)
    stop("Please provide featurecount file.", call.=FALSE)
}
if (is.null(opt$bam_suffix)){
    print_help(opt_parser)
    stop("Please provide bam suffix in header of featurecount file.", call.=FALSE)
}

################################################
################################################
## READ IN COUNTS FILE												##
################################################
################################################

count.table <- read.delim(file=opt$featurecount_file,header=TRUE,skip=1)
colnames(count.table) <- gsub(opt$bam_suffix,"",colnames(count.table))
colnames(count.table) <- as.character(lapply(colnames(count.table), function (x) tail(strsplit(x,'.',fixed=TRUE)[[1]],1)))
rownames(count.table) <- count.table$Geneid
interval.table <- count.table[,1:6]
count.table <- count.table[,7:ncol(count.table),drop=FALSE]

################################################
################################################
## RUN DESEQ2																	##
################################################
################################################

if (file.exists(opt$outdir) == FALSE) {
    dir.create(opt$outdir,recursive=TRUE)
}
setwd(opt$outdir)

samples.vec <- sort(colnames(count.table))
groups <- substr(samples.vec, 1, nchar(samples.vec)-3)
print(unique(groups))
if (length(unique(groups)) == 1) {
    quit(save = "no", status = 0, runLast = FALSE)
}

DDSFile <- paste(opt$outprefix,".dds.rld.RData",sep="")
if (file.exists(DDSFile) == FALSE) {
    counts <- count.table[,samples.vec,drop=FALSE]
    coldata <- data.frame(row.names=colnames(counts),condition=groups)
    dds <- DESeqDataSetFromMatrix(countData = round(counts), colData = coldata, design = ~ condition)
    dds <- DESeq(dds)
    rld <- rlog(dds)
    save(dds,rld,file=DDSFile)
}

################################################
################################################
## PLOT QC  																	##
################################################
################################################

PlotFile <- paste(opt$outprefix,".plots.pdf",sep="")
if (file.exists(PlotFile) == FALSE) {
    pdf(file=PlotFile,onefile=TRUE,width=7,height=7)

    ## PCA
    pca.data <- DESeq2::plotPCA(rld,intgroup=c("condition"),returnData=TRUE)
    percentVar <- round(100 * attr(pca.data, "percentVar"))
    plot <- ggplot(pca.data, aes(PC1, PC2, color=condition)) +
            geom_point(size=3) +
            xlab(paste0("PC1: ",percentVar[1],"% variance")) +
            ylab(paste0("PC2: ",percentVar[2],"% variance")) +
            theme(panel.grid.major = element_blank(),
                  panel.grid.minor = element_blank(),
                  panel.background = element_blank(),
                  panel.border = element_rect(colour = "black", fill=NA, size=1))
    print(plot)

    ## WRITE PC1 vs PC2 VALUES TO FILE
    pca.vals <- pca.data[,1:2]
    colnames(pca.vals) <- paste(colnames(pca.vals),paste(percentVar,'% variance',sep=""), sep=": ")
    pca.vals <- cbind(sample = rownames(pca.vals), pca.vals)
    write.table(pca.vals,file=paste(opt$outprefix,".pca.vals.txt",sep=""),row.names=FALSE,col.names=TRUE,sep="\t",quote=TRUE)

    ## SAMPLE CORRELATION HEATMAP
    sampleDists <- dist(t(assay(rld)))
    sampleDistMatrix <- as.matrix(sampleDists)
    colors <- colorRampPalette( rev(brewer.pal(9, "Blues")) )(255)
    pheatmap(sampleDistMatrix,clustering_distance_rows=sampleDists,clustering_distance_cols=sampleDists,col=colors)

    ## WRITE SAMPLE DISTANCES TO FILE
    write.table(cbind(sample = rownames(sampleDistMatrix), sampleDistMatrix),file=paste(opt$outprefix,".sample.dists.txt",sep=""),row.names=FALSE,col.names=TRUE,sep="\t",quote=FALSE)

    dev.off()
}

################################################
################################################
## SAVE SIZE FACTORS  												##
################################################
################################################

SizeFactorsDir <- "sizeFactors/"
if (file.exists(SizeFactorsDir) == FALSE) {
    dir.create(SizeFactorsDir,recursive=TRUE)
}

NormFactorsFile <- paste(SizeFactorsDir,opt$outprefix,".sizeFactors.RData",sep="")
if (file.exists(NormFactorsFile) == FALSE) {
    normFactors <- sizeFactors(dds)
    save(normFactors,file=NormFactorsFile)

    for (name in names(sizeFactors(dds))) {
        sizeFactorFile <- paste(SizeFactorsDir,name,opt$outsuffix,".sizeFactor.txt",sep="")
        if (file.exists(sizeFactorFile) == FALSE) {
            write(as.numeric(sizeFactors(dds)[name]),file=sizeFactorFile)
        }
    }
}

################################################
################################################
## WRITE LOG FILE   													##
################################################
################################################

LogFile <- paste(opt$outprefix,".log",sep="")
if (file.exists(LogFile) == FALSE) {
    cat("\nSamples =",samples.vec,"\n\n",file=LogFile,append=TRUE,sep=', ')
    cat("Groups =",groups,"\n\n",file=LogFile,append=TRUE,sep=', ')
    cat("Dimensions of count matrix =",dim(counts),"\n\n",file=LogFile,append=FALSE,sep=' ')
    cat("\n",file=LogFile,append=TRUE,sep='')
}

################################################
################################################
## LOOP THROUGH COMPARISONS    								##
################################################
################################################

ResultsFile <- paste(opt$outprefix,".results.txt",sep="")
if (file.exists(ResultsFile) == FALSE) {

    raw.counts <- counts(dds,normalized=FALSE)
    colnames(raw.counts) <- paste(colnames(raw.counts),'raw',sep='.')
    pseudo.counts <- counts(dds,normalized=TRUE)
    colnames(pseudo.counts) <- paste(colnames(pseudo.counts),'pseudo',sep='.')

    deseq2_results_list <- list()
    comparisons <- combn(unique(groups),2)
    for (idx in 1:ncol(comparisons)) {

        control.group <- comparisons[1,idx]
        treat.group <- comparisons[2,idx]
        CompPrefix <- paste(control.group,treat.group,sep="vs")
        cat("Saving results for ",CompPrefix," ...\n",sep="")

        CompOutDir <- paste(CompPrefix,'/',sep="")
        if (file.exists(CompOutDir) == FALSE) {
            dir.create(CompOutDir,recursive=TRUE)
        }

        control.samples <- samples.vec[which(groups == control.group)]
        treat.samples <- samples.vec[which(groups == treat.group)]
        comp.samples <- c(control.samples,treat.samples)

        comp.results <- results(dds,contrast=c("condition",c(control.group,treat.group)))
        comp.df <- as.data.frame(comp.results)
        comp.table <- cbind(interval.table, as.data.frame(comp.df), raw.counts[,paste(comp.samples,'raw',sep='.')], pseudo.counts[,paste(comp.samples,'pseudo',sep='.')])

        ## WRITE RESULTS FILE
        CompResultsFile <- paste(CompOutDir,CompPrefix,opt$outsuffix,".deseq2.results.txt",sep="")
        write.table(comp.table, file=CompResultsFile, col.names=TRUE, row.names=FALSE, sep='\t', quote=FALSE)

        ## FILTER RESULTS BY FDR & LOGFC AND WRITE RESULTS FILE
        pdf(file=paste(CompOutDir,CompPrefix,opt$outsuffix,".deseq2.plots.pdf",sep=""),width=10,height=8)
        if (length(comp.samples) > 2) {
            for (MIN_FDR in c(0.01,0.05)) {

                ## SUBSET RESULTS BY FDR
                pass.fdr.table <- subset(comp.table, padj < MIN_FDR)
                pass.fdr.up.table <- subset(comp.table, padj < MIN_FDR & log2FoldChange > 0)
                pass.fdr.down.table <- subset(comp.table, padj < MIN_FDR & log2FoldChange < 0)

                ## SUBSET RESULTS BY FDR AND LOGFC
                pass.fdr.logFC.table <- subset(comp.table, padj < MIN_FDR & abs(log2FoldChange) >= 1)
                pass.fdr.logFC.up.table <- subset(comp.table, padj < MIN_FDR & abs(log2FoldChange) >= 1 & log2FoldChange > 0)
                pass.fdr.logFC.down.table <- subset(comp.table, padj < MIN_FDR & abs(log2FoldChange) >= 1 & log2FoldChange < 0)

                ## WRITE RESULTS FILE
                CompResultsFile <- paste(CompOutDir,CompPrefix,opt$outsuffix,".deseq2.FDR",MIN_FDR,".results.txt",sep="")
                CompBEDFile <- paste(CompOutDir,CompPrefix,opt$outsuffix,".deseq2.FDR",MIN_FDR,".results.bed",sep="")
                write.table(pass.fdr.table, file=CompResultsFile, col.names=TRUE, row.names=FALSE, sep='\t', quote=FALSE)
                write.table(pass.fdr.table[,c("Chr","Start","End","Geneid","log2FoldChange","Strand")], file=CompBEDFile, col.names=FALSE, row.names=FALSE, sep='\t', quote=FALSE)

                CompResultsFile <- paste(CompOutDir,CompPrefix,opt$outsuffix,".deseq2.FDR",MIN_FDR,".FC2.results.txt",sep="")
                CompBEDFile <- paste(CompOutDir,CompPrefix,opt$outsuffix,".deseq2.FDR",MIN_FDR,".FC2.results.bed",sep="")
                write.table(pass.fdr.logFC.table, file=CompResultsFile, col.names=TRUE, row.names=FALSE, sep='\t', quote=FALSE)
                write.table(pass.fdr.logFC.table[,c("Chr","Start","End","Geneid","log2FoldChange","Strand")], file=CompBEDFile, col.names=FALSE, row.names=FALSE, sep='\t', quote=FALSE)

                ## MA PLOT & VOLCANO PLOT
                DESeq2::plotMA(comp.results, main=paste("MA plot FDR <= ",MIN_FDR,sep=""), ylim=c(-2,2),alpha=MIN_FDR)
                plot(comp.table$log2FoldChange, -1*log10(comp.table$padj), col=ifelse(comp.table$padj<=MIN_FDR, "red", "black"), xlab="logFC", ylab="-1*log10(FDR)", main=paste("Volcano plot FDR <=",MIN_FDR,sep=" "), pch=20)

                ## ADD COUNTS TO LOGFILE
                cat(CompPrefix," genes with FDR <= ",MIN_FDR,": ",nrow(pass.fdr.table)," (up=",nrow(pass.fdr.up.table),", down=",nrow(pass.fdr.down.table),")","\n",file=LogFile,append=TRUE,sep="")
                cat(CompPrefix," genes with FDR <= ",MIN_FDR," & FC > 2: ",nrow(pass.fdr.logFC.table)," (up=",nrow(pass.fdr.logFC.up.table),", down=",nrow(pass.fdr.logFC.down.table),")","\n",file=LogFile,append=TRUE,sep="")

            }
            cat("\n",file=LogFile,append=TRUE,sep="")
        }

        ## SAMPLE CORRELATION HEATMAP
        rld.subset <- assay(rld)[,comp.samples]
        sampleDists <- dist(t(rld.subset))
        sampleDistMatrix <- as.matrix(sampleDists)
        colors <- colorRampPalette( rev(brewer.pal(9, "Blues")) )(255)
        pheatmap(sampleDistMatrix,clustering_distance_rows=sampleDists,clustering_distance_cols=sampleDists,col=colors)

        ## SCATTER PLOT FOR RLOG COUNTS
        combs <- combn(comp.samples,2,simplify=FALSE)
        clabels <- sapply(combs,function(x){paste(x,collapse=' & ')})
        plotdat <- data.frame(x=unlist(lapply(combs, function(x){rld.subset[, x[1] ]})),y=unlist(lapply(combs, function(y){rld.subset[, y[2] ]})),comp=rep(clabels, each=nrow(rld.subset)))
        plot <- xyplot(y~x|comp,plotdat,
                       panel=function(...){
                           panel.xyplot(...)
                           panel.abline(0,1,col="red")
                       },
                       par.strip.text=list(cex=0.5))
        print(plot)
        dev.off()

        colnames(comp.df) <- paste(CompPrefix,".",colnames(comp.df),sep="")
        deseq2_results_list[[idx]] <- comp.df

    }

    ## WRITE RESULTS FROM ALL COMPARISONS TO FILE
    deseq2_results_table <- cbind(interval.table,do.call(cbind, deseq2_results_list),raw.counts,pseudo.counts)
    write.table(deseq2_results_table, file=ResultsFile, col.names=TRUE, row.names=FALSE, sep='\t', quote=FALSE)

}

################################################
################################################
## R SESSION INFO															##
################################################
################################################

RLogFile <- "R_sessionInfo.log"
if (file.exists(RLogFile) == FALSE) {
    sink(RLogFile)
    a <- sessionInfo()
    print(a)
    sink()
}

################################################
################################################
################################################
################################################
