#!/usr/bin/env Rscript

# Adapting code by Elmar Pruesse from phyloFlash_heatmap.R

## FUNCTIONS ###################################################################

required.packages = c("optparse", "ggplot2", "reshape2", "ggdendro", "gtable", "plyr", "RColorBrewer");
check_libraries <- function() {
  missing.packages <- required.packages[!(required.packages %in% installed.packages())];
  if (length(missing.packages)) {
    msg("Additional packages required: ", missing.packages);
    if (options("repos")[[1]] == "@CRAN@") {
      options(repos = "http://cran.r-project.org")
    }
    install.packages(missing.packages);
  }
  missing.packages <- required.packages[!(required.packages %in% installed.packages())];
  if (length(missing.packages)) {
    err("Unable to install these required packages: ", missing.packages, "\n",
      "Please install these manually. They are required by phyloFlash_heatmap.R");
  }
}

load_libraries <- function() {
  library(ggplot2);
  library(reshape2);
  library(ggdendro);
  library(gtable);
  library(plyr);
  library(RColorBrewer);
}

makepalette <- function (n, brewer.name='Set3', othercolor='grey') {
  # Define palette for taxa, using RColorBrewer Set3 as default for n colors <= 12
  # otherwise attempt to "stretcH" the palette with colorRampPalette
  # othercolor is the default color for "Other" taxa
  
  # Account for different maximum n for different preset palettes
  max.n <- switch(brewer.name, 
                  "Set3" = 12,
                  "Accent" = 8,
                  "Dark2" = 8,
                  "Paired" = 12,
                  "Pastel1" = 9,
                  "Pastel2" = 8,
                  "Set1" = 9,
                  "Set2" = 8
                  )
  
  if (n <= max.n ) {
    out.palette <- brewer.pal(n, name=brewer.name)
    out.palette <- c(out.palette,othercolor)
  } else {
    out.palette <- colorRampPalette(brewer.pal(max.n, name=brewer.name))(n)
    out.palette <- c(out.palette,othercolor)
  }
  return(out.palette)
}

## MAIN ########################################################################

suppressPackageStartupMessages(library(optparse));

options <- list(
  make_option(
    c("-t", "--toptaxa"),
    type="integer",
    default=10,
    action="store",
    help="Number of taxa to display in the barplot. By default takes the top 10
                by total proportional abundance in the library"
    ),
  make_option(
    c("-f", "--file"),
    type="character",
    action="store",
    help="CSV file containing three columns: Taxon, sample, and counts"
    ),
  make_option(
    c("-o", "--out"),
    type="character",
    action="store",
    default="TEST",
    help="Name of output PDF or PNG file"
    ),
  make_option(
    c("-p","--palette"),
    type="character",
    action="store",
    default="Set3",
    help="Palette name for taxon colors. One of the qualitative palettes from the
                  ColorBrewer2 set: Accent, Dark2, Paired, Pastel1, Pastel2, Set1, Set2, or Set3."
  ),
  make_option(
    c("-s","--subset"),
    type="character",
    action="store",
    default=NA,
    help="Display only subset from this taxon (e.g. show only Bacteria). Supply
                  full taxon string prefix, excluding trailing semicolon."
  ),
  make_option(
    c("-r","--rawval"),
    type="logical",
    action="store_true",
    default=FALSE,
    help="Plot raw counts rather than proportions"
  )
);

parser <- OptionParser(
  option_list=options,
  usage="usage: %prog [options]",
  description="Generate a barplot of NTU abundances by sample"
);

conf <- parse_args(parser, positional_arguments = TRUE);
if (length(conf$options$file) != 1) {
  cat ("ERROR: File not specified to option --file \n")
  print_help(parser);
  quit(status=2);
}

load_libraries();

# Read data
d <- read.csv(conf$options$file[1], sep=",", header=F)
names(d) <- c('taxon','sample','counts')
topshow <- conf$options$toptaxa[1]

if (!is.na(conf$options$subset[1])) {
  d <- d[grep(paste(c("^",conf$options$subset[1]),sep="",collapse=""),
              d$taxon,
              perl=TRUE,
              value=FALSE),]
}

# Convert raw read counts to proportions per sample
if (conf$options$rawval[1]) {
  dd <- d
  dd$prop <- d$counts
} else {
  dd <- ddply(d,'sample', function(x) { sumcounts <- sum(x$counts)
                                        data.frame(taxon = x$taxon,
                                          counts = x$counts,
                                          prop = x$counts/sumcounts)
                                      })
}

dd.totals <- ddply(dd,'taxon',function(x) { totalprop <- sum(x$prop)
                                            data.frame(totalprop=totalprop)
                                          })

# Reorder taxon names by abundance
taxonnames.ordered <- as.vector(dd.totals[order(dd.totals$totalprop,decreasing=T),'taxon'])
taxonnames.renamed <- c(taxonnames.ordered[0:topshow],
                        rep('Other',length(taxonnames.ordered) - topshow))
rename.df <- data.frame(taxon=taxonnames.ordered,
                        rename=taxonnames.renamed)

# Merge into main data frame to put low-abundance taxa into lump 'Other'
dd.rename <- merge(dd,rename.df,by='taxon')

# Rearrange levels of the names by abundance rather than alphabetically
dd.rename$rename <- factor(dd.rename$rename,levels=taxonnames.renamed[0:topshow+1])

# Custom palette
dd.palette <- makepalette (n=topshow,brewer.name=conf$options$palette[1],othercolor='grey')

# Draw plot
dd.rename.barplot <- (ggplot(dd.rename, aes(sample,prop))
                      + geom_bar(aes(fill=rename),stat='identity')
                      + scale_fill_manual(values=dd.palette)
                      + labs(x="Library",y="Proportion of SSU rRNA reads", fill="Taxon")
                      + theme(axis.text.x = element_text(angle=90, hjust=1))
                      )

# Write file
outname <- conf$options$out[1]
# Adjust width of plot
num.samples <- length(levels(dd.rename$sample))
width <- 360 + 80 * num.samples
height <- 480

# Choose which output format by output prefix (adapted from heatmap script)
switch(tail(n=1,strsplit(conf$options$out, "[.]")[[1]]),
  png = png(file = conf$options$out,
    width=width, height=height),
  pdf = pdf(file = conf$options$out,
    width=width/72, height=height/72)
  );
dd.rename.barplot
dev.off()
