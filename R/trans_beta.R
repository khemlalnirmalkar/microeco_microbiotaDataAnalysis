#' @title Create trans_beta object for the analysis of distance matrix of beta-diversity.
#'
#' @description
#' This class is a wrapper for a series of beta-diversity related analysis, 
#' including several ordination calculations and plotting based on An et al. (2019) <doi:10.1016/j.geoderma.2018.09.035>, group distance comparision, 
#' clustering, perMANOVA based on Anderson al. (2008) <doi:10.1111/j.1442-9993.2001.01070.pp.x> and PERMDISP.
#' Please also cite the original paper: An et al. (2019). Soil bacterial community structure in Chinese wetlands. Geoderma, 337, 290-299.
#'
#' @export
trans_beta <- R6Class(classname = "trans_beta",
	public = list(
		#' @param dataset the object of \code{\link{microtable}} Class.
		#' @param measure default NULL; bray, jaccard, wei_unifrac or unwei_unifrac, or other name of matrix you add; 
		#' 	 beta diversity index used for ordination, manova or group distance.
		#' @param group default NULL; sample group used for manova, betadisper or group distance.
		#' @return parameters stored in the object.
		#' @examples
		#' data(dataset)
		#' t1 <- trans_beta$new(dataset = dataset, measure = "bray", group = "Group")
		initialize = function(
			dataset = NULL, 
			measure = NULL, 
			group = NULL
			) {
			if(is.null(dataset)){
				stop("dataset is necessary !")
			}
			if(!is.null(measure)){
				if(!measure %in% c(names(dataset$beta_diversity), 1:length(dataset$beta_diversity))){
					stop("Input measure should be one of beta_diversity distance in dataset !")
				}else{
					self$use_matrix <- dataset$beta_diversity[[measure]]
				}
			}
			self$sample_table <- dataset$sample_table
			self$measure <- measure
			self$group <- group
			use_dataset <- clone(dataset)
			use_dataset$phylo_tree <- NULL
			use_dataset$rep_fasta <- NULL
			use_dataset$taxa_abund <- NULL
			use_dataset$alpha_diversity <- NULL
			self$dataset <- use_dataset
		},
		#' @description
		#' Ordination based on An et al. (2019) <doi:10.1016/j.geoderma.2018.09.035>.
		#'
		#' @param ordination default "PCoA"; "PCA", "PCoA" or "NMDS". PCA: principal component analysis; 
		#' 	  PCoA: principal coordinates analysis; NMDS: non-metric multidimensional scaling.
		#' @param ncomp default 3; the returned dimensions.
		#' @param trans_otu default FALSE; whether species abundance will be square transformed, used for PCA.
		#' @param scale_species default FALSE; whether species loading in PCA will be scaled.
		#' @return res_ordination stored in the object.
		#' @examples
		#' t1$cal_ordination(ordination = "PCoA")		
		cal_ordination = function(
			ordination = "PCoA",
			ncomp = 3,
			trans_otu = FALSE, 
			scale_species = FALSE		
			){
			if(is.null(ordination)){
				stop("Input ordination should not be NULL !")
			}
			if(!ordination %in% c("PCA", "PCoA", "NMDS")){
				stop("Input ordination should be one of 'PCA', 'PCoA' and 'NMDS' !")
			}
			dataset <- self$dataset
			if(ordination == "PCA"){
				plot.x <- "PC1"
				plot.y <- "PC2"
				if(trans_otu == T){
					abund1 <- sqrt(dataset$otu_table)
				}else{
					abund1 <- dataset$otu_table
				}
				model <- rda(t(abund1))
				expla <- round(model$CA$eig/model$CA$tot.chi*100,1)
				scores <- scores(model, choices = 1:ncomp)$sites
				combined <- cbind.data.frame(scores, dataset$sample_table)

				if(is.null(dataset$tax_table)){
					loading <- scores(model, choices = 1:ncomp)$species
				}else{
					loading <- cbind.data.frame(scores(model, choices = 1:ncomp)$species, dataset$tax_table)
				}
				loading <- cbind.data.frame(loading, rownames(loading))

				if(scale_species == T){
					maxx <- max(abs(scores[,plot.x]))/max(abs(loading[,plot.x]))
					loading[, plot.x] <- loading[, plot.x] * maxx * 0.8
					maxy <- max(abs(scores[,plot.y]))/max(abs(loading[,plot.y]))
					loading[, plot.y] <- loading[, plot.y] * maxy * 0.8
				}

				species <- cbind(loading, loading[,plot.x]^2 + loading[,plot.y]^2)
				colnames(species)[ncol(species)] <- "dist"
				species <- species[with(species, order(-dist)), ]
				outlist <- list(model = model, scores = combined, loading = species, eig = expla)
			}
			if(ordination %in% c("PCoA", "NMDS")){
				if(is.null(self$use_matrix)){
					stop("Please recreate the object and set the parameter measure !")
				}
			}
			if(ordination == "PCoA"){
				model <- ape::pcoa(as.dist(self$use_matrix))
				combined <- cbind.data.frame(model$vectors[,1:ncomp], dataset$sample_table)
				pco_names <- paste0("PCo", 1:10)
				colnames(combined)[1:ncomp] <- pco_names[1:ncomp]
				expla <- round(model$values[,1]/sum(model$values[,1])*100, 1)
				expla <- expla[1:ncomp]
				names(expla) <- pco_names[1:ncomp]
				outlist <- list(model = model, scores = combined, eig = expla)
			}
			if(ordination == "NMDS"){
				model <- vegan::metaMDS(as.dist(self$use_matrix))
				combined <- cbind.data.frame(model$points, dataset$sample_table)
				outlist <- list(model = model, scores = combined)
			}
			self$res_ordination <- outlist
			message('The ordination result is stored in object$res_ordination ...')
			self$ordination <- ordination
		},
		#' @description
		#' Plotting the ordination result based on An et al. (2019) <doi:10.1016/j.geoderma.2018.09.035>.
		#'
		#' @param plot_type default "point"; one or more elements of "point", "ellipse", "chull" and "centroid".
		#'   \describe{
		#'     \item{\strong{'point'}}{add point}
		#'     \item{\strong{'ellipse'}}{add confidence ellipse for points of each group}
		#'     \item{\strong{'chull'}}{add convex hull for points of each group}
		#'     \item{\strong{'centroid'}}{add centroid line of each group}
		#'   }
		#' @param color_values default RColorBrewer::brewer.pal(8, "Dark2"); colors palette for different groups.
		#' @param shape_values default c(16, 17, 7, 8, 15, 18, 11, 10, 12, 13, 9, 3, 4, 0, 1, 2, 14); a vector for point shape types of groups, see ggplot2 tutorial.
		#' @param plot_color default NULL; a colname of sample_table to assign colors to different groups in plot.
		#' @param plot_shape default NULL; a colname of sample_table to assign shapes to different groups in plot.
		#' @param plot_group_order default NULL; a vector used to order the groups in the legend of plot.
		#' @param add_sample_label default NULL; the column name in sample table, if provided, show the point name in plot.
		#' @param point_size default 3; point size in plot when "point" is in plot_type.
		#' @param point_alpha default .8; point transparency in plot when "point" is in plot_type.
		#' @param centroid_segment_alpha default 0.6; segment transparency in plot when "centroid" is in plot_type.
		#' @param centroid_segment_size default 1; segment size in plot when "centroid" is in plot_type.
		#' @param centroid_segment_linetype default 3; the line type related with centroid in plot when "centroid" is in plot_type.
		#' @param ellipse_chull_fill default TRUE; whether fill colors to the area of ellipse or chull.
		#' @param ellipse_chull_alpha default 0.1; color transparency in the ellipse or convex hull depending on whether "ellipse" or "centroid" is in plot_type.
		#' @param ellipse_level default .9; confidence level of ellipse when "ellipse" is in plot_type.
		#' @param ellipse_type default "t"; ellipse type when "ellipse" is in plot_type; see type in \code{\link{stat_ellipse}}.
		#' @return ggplot.
		#' @examples
		#' t1$plot_ordination(plot_type = "point")
		#' t1$plot_ordination(plot_color = "Group", plot_shape = "Group", plot_type = "point")
		#' t1$plot_ordination(plot_color = "Group", plot_type = c("point", "ellipse"))
		#' t1$plot_ordination(plot_color = "Group", plot_type = c("point", "chull"))
		#' t1$plot_ordination(plot_color = "Group", plot_type = c("point", "centroid"), 
		#' 	  centroid_segment_linetype = 1)
		plot_ordination = function(
			plot_type = "point",
			color_values = RColorBrewer::brewer.pal(8, "Dark2"), 
			shape_values = c(16, 17, 7, 8, 15, 18, 11, 10, 12, 13, 9, 3, 4, 0, 1, 2, 14),
			plot_color = NULL,
			plot_shape = NULL,
			plot_group_order = NULL,
			add_sample_label = NULL,
			point_size = 3,
			point_alpha = 0.8,
			centroid_segment_alpha = 0.6,
			centroid_segment_size = 1,
			centroid_segment_linetype = 3,
			ellipse_chull_fill = TRUE,
			ellipse_chull_alpha = 0.1,
			ellipse_level = 0.9,
			ellipse_type = "t"
			){
			ordination <- self$ordination
			if(is.null(ordination)){
				stop("Please first run cal_ordination function !")
			}
			if(is.null(plot_color)){
				if(any(c("ellipse", "chull", "centroid") %in% plot_type)){
					stop("Plot ellipse or chull or centroid need groups! Please provide plot_color parameter!")
				}
			}
			if(! all(plot_type %in% c("point", "ellipse", "chull", "centroid"))){
				message("There maybe a typo in your plot_type input! plot_type should be one or more from 'point', 'ellipse', 'chull' and 'centroid'!")
			}
			combined <- self$res_ordination$scores
			eig <- self$res_ordination$eig
			model <- self$res_ordination$model
			plot_x <- colnames(self$res_ordination$scores)[1]
			plot_y <- colnames(self$res_ordination$scores)[2]
			
			if(!is.null(plot_group_order)){
				combined[, plot_color] %<>% factor(., levels = plot_group_order)
			}
			
			p <- ggplot(combined, aes_string(x = plot_x, y = plot_y, color = plot_color, shape = plot_shape))
			if("point" %in% plot_type){
				p <- p + geom_point(alpha = point_alpha, size = point_size)
			}
			if(ordination %in% c("PCA", "PCoA")){
				p <- p + xlab(paste(plot_x, " [", eig[plot_x],"%]", sep = "")) + 
					ylab(paste(plot_y, " [", eig[plot_y],"%]", sep = ""))
			}
			if(ordination == "NMDS"){
				p <- p + annotate("text", x = max(combined[,1]), y = max(combined[,2]) + 0.05, label = round(model$stress, 2), parse=TRUE)
			}
			if("centroid" %in% plot_type){
				centroid_xy <- data.frame(group = combined[, plot_color], x = combined[, plot_x], y = combined[, plot_y]) %>%
					dplyr::group_by(group) %>%
					dplyr::summarise(cx = mean(x), cy = mean(y)) %>%
					as.data.frame()
				combined_centroid_xy <- merge(combined, centroid_xy, by.x = plot_color, by.y = "group")
				p <- p + geom_segment(
					data = combined_centroid_xy, 
					aes_string(x = plot_x, xend = "cx", y = plot_y, yend = "cy", color = plot_color),
					alpha = centroid_segment_alpha, 
					size = centroid_segment_size, 
					linetype = centroid_segment_linetype
				)
			}
			if(any(c("ellipse", "chull") %in% plot_type)){
				if(ellipse_chull_fill){
					ellipse_chull_fill_color <- plot_color
				}else{
					ellipse_chull_fill_color <- NULL
					ellipse_chull_alpha <- 0
				}
				mapping <- aes_string(x = plot_x, y = plot_y, group = plot_color, color = plot_color, fill = ellipse_chull_fill_color)
				if("ellipse" %in% plot_type){
					p <- p + ggplot2::stat_ellipse(
						mapping = mapping, 
						data = combined, 
						level = ellipse_level, 
						type = ellipse_type, 
						alpha = ellipse_chull_alpha, 
						geom = "polygon"
						)
				}
				if("chull" %in% plot_type){
					p <- p + ggpubr::stat_chull(
						mapping = mapping, 
						data = combined, 
						alpha = ellipse_chull_alpha,
						geom = "polygon"
						)
				}
				if(ellipse_chull_fill){
					p <- p + scale_fill_manual(values = color_values)
				}
			}
			if(!is.null(add_sample_label)){
				p <- p + ggrepel::geom_text_repel(aes_string(label = add_sample_label))
			}
			if(!is.null(plot_color)){
				p <- p + scale_color_manual(values = color_values)
			}
			if(!is.null(plot_shape)){
				p <- p + scale_shape_manual(values = shape_values)
			}
			p
		},
		#' @description
		#' Calculate perMANOVA based on Anderson al. (2008) <doi:10.1111/j.1442-9993.2001.01070.pp.x> and R vegan adonis2 function.
		#'
		#' @param manova_all default TRUE; TRUE represents test for all the groups, i.e. the overall test;
		#'    FALSE represents test for all the paired groups.
		#' @param manova_set default NULL; other specified group set for manova, such as "Group + Type" and "Group*Type"; see also \code{\link{adonis2}}.
		#' @param group default NULL; a column name of sample_table used for manova. If NULL, search group stored in the object.
		#' @param p_adjust_method default "fdr"; p.adjust method when manova_all = FALSE; see method parameter of p.adjust function for available options.
		#' @param ... parameters passed to \code{\link{adonis2}} function of vegan package.
		#' @return res_manova stored in object.
		#' @examples
		#' t1$cal_manova(manova_all = TRUE)
		cal_manova = function(
			manova_all = TRUE,
			manova_set = NULL,
			group = NULL,
			p_adjust_method = "fdr",
			...
			){
			if(is.null(self$use_matrix)){
				stop("Please recreate the object and set the parameter measure !")
			}
			use_matrix <- self$use_matrix
			metadata <- self$sample_table
			if(!is.null(manova_set)){
				use_formula <- reformulate(manova_set, substitute(as.dist(use_matrix)))
				self$res_manova <- adonis2(use_formula, data = metadata, ...)
			}else{
				if(is.null(group)){
					if(is.null(self$group)){
						stop("Please provide the group parameter!")
					}else{
						group <- self$group
					}
				}
				if(manova_all){
					use_formula <- reformulate(group, substitute(as.dist(use_matrix)))
					self$res_manova <- adonis2(use_formula, data = metadata, ...)
				}else{
					self$res_manova <- private$paired_group_manova(
						sample_info_use = metadata, 
						use_matrix = use_matrix, 
						group = group, 
						measure = self$measure, 
						p_adjust_method = p_adjust_method,
						...
					)
				}
			}
			message('The result is stored in object$res_manova ...')
		},
		#' @description
		#' A wrapper for betadisper function in vegan package for multivariate homogeneity test of groups dispersions.
		#'
		#' @param ... parameters passed to \code{\link{betadisper}} function.
		#' @return res_betadisper stored in object.
		#' @examples
		#' t1$cal_betadisper()
		cal_betadisper = function(...){
			if(is.null(self$use_matrix)){
				stop("Please recreate the object and set the parameter measure !")
			}
			use_matrix <- self$use_matrix
			res1 <- betadisper(as.dist(use_matrix), self$sample_table[, self$group], ...)
			res2 <- permutest(res1, pairwise = TRUE)
			self$res_betadisper <- res2
			message('The result is stored in object$res_betadisper ...')
		},
		#' @description
		#' Transform sample distances within groups or between groups.
		#'
		#' @param within_group default TRUE; whether transform sample distance within groups, if FALSE, transform sample distance between any two groups.
		#' @return res_group_distance stored in object.
		#' @examples
		#' \donttest{
		#' t1$cal_group_distance(within_group = TRUE)
		#' }
		cal_group_distance = function(within_group = TRUE){
			if(within_group == T){
				self$res_group_distance <- private$within_group_distance(distance = self$use_matrix, sampleinfo=self$sample_table, type = self$group)
			}else{
				self$res_group_distance <- private$between_group_distance(distance = self$use_matrix, sampleinfo=self$sample_table, type = self$group)
			}
			message('The result is stored in object$res_group_distance ...')
		},
		#' @description
		#' Plotting the distance between samples within or between groups.
		#'
		#' @param plot_group_order default NULL; a vector used to order the groups in the plot.
		#' @param color_values colors for presentation.
		#' @param distance_pair_stat default FALSE; whether do the paired comparisions.
		#' @param hide_ns default FALSE; whether hide the "ns" pairs, i.e. non significant comparisions.
		#' @param hide_ns_more default NULL; character vector; available when hide_ns = TRUE; if provided, used for the specific significance filtering, such as c("ns", "*").
		#' @param pair_compare_filter_match default NULL; only available when hide_ns = FALSE; if provided, remove the matched groups; use the regular express to match the paired groups.
		#' @param pair_compare_filter_select default NULL; numeric vector;only available when hide_ns = FALSE; if provided, only select those input groups.
		#'   This parameter must be a numeric vector used to select the paired combination of groups. For example, pair_compare_filter_select = c(1, 3) 
		#'   can be used to select "CW"-"IW" and "IW"-"TW" from all the three pairs "CW"-"IW", "CW"-"TW" and "IW"-"TW" of ordered groups ("CW", "IW", "TW").
		#'   The parameter pair_compare_filter_select and pair_compare_filter_match can not be both used together.
		#' @param pair_compare_method default wilcox.test; wilcox.test, kruskal.test, t.test or anova.
		#' @param plot_distance_xtype default NULL; number used to make x axis text generate angle.
		#' @return ggplot.
		#' @examples
		#' \donttest{
		#' t1$plot_group_distance(distance_pair_stat = TRUE)
		#' t1$plot_group_distance(distance_pair_stat = TRUE, hide_ns = TRUE)
		#' t1$plot_group_distance(distance_pair_stat = TRUE, hide_ns = TRUE, hide_ns_more = c("ns", "*"))
		#' t1$plot_group_distance(distance_pair_stat = TRUE, pair_compare_filter_select = 3)
		#' }
		plot_group_distance = function(
			plot_group_order = NULL,
			color_values = RColorBrewer::brewer.pal(8, "Dark2"),
			distance_pair_stat = FALSE,
			hide_ns = FALSE,
			hide_ns_more = NULL,
			pair_compare_filter_match = NULL,
			pair_compare_filter_select = NULL,
			pair_compare_method = "wilcox.test",
			plot_distance_xtype = NULL
			){
			group_distance <- self$res_group_distance
			group <- self$group
			if(self$measure %in% c("wei_unifrac", "unwei_unifrac", "bray", "jaccard")){
				titlename <- switch(self$measure, 
					wei_unifrac = "Weighted Unifrac", 
					unwei_unifrac = "Unweighted Unifrac", 
					bray = "Bray-Curtis", 
					jaccard = "Jaccard")
				ylabname <- paste0(titlename, " distance")
			}else{
				ylabname <- self$measure
			}
			if (!is.null(plot_group_order)) {
				group_distance[, group] %<>% factor(., levels = plot_group_order)
			}else{
				group_distance[, group] %<>% as.factor
			}
			message("The ordered groups are ", paste0(levels(group_distance[, group]), collapse = " "), " ...")
			
			p <- ggplot(group_distance, aes_string(x = group, y = "value", color = group)) +
				theme_bw() +
				theme(panel.grid=element_blank()) +
				geom_boxplot(outlier.size =1,width=.6,linetype=1) +
				stat_summary(fun="mean", geom="point", shape=20, size=3, fill="white") +
				xlab("") +
				ylab(ylabname) +
				theme(axis.text=element_text(size=12)) +
				theme(axis.title=element_text(size=17), legend.position = "none") +
				scale_color_manual(values=color_values)
			if(!is.null(plot_distance_xtype)){
				p <- p + theme(axis.text.x = element_text(angle = plot_distance_xtype, colour = "black", vjust = 1, hjust = 1, size = 10))
			}
			if(distance_pair_stat == T){
				# first generate pairs
				comparisons_list <- levels(group_distance[, group]) %>% 
					combn(., 2)
				# filter based on the significance
				if(hide_ns){
					pre_filter <- ggpubr::compare_means(reformulate(group, "value"), group_distance)
					if(is.null(hide_ns_more)){
						filter_mark <- "ns"
					}else{
						filter_mark <- hide_ns_more
					}
					comparisons_list %<>% .[, !(pre_filter$p.signif %in% filter_mark), drop = FALSE]
				}else{
					# remove specific groups
					if(!is.null(pair_compare_filter_match) & !is.null(pair_compare_filter_select)){
						stop("The parameter pair_compare_filter_select and pair_compare_filter_match can not be both used together!")
					}
					if(!is.null(pair_compare_filter_match)){
						comparisons_list %<>% {.[, unlist(lapply(as.data.frame(.), function(x) any(grepl(pair_compare_filter_match, x)))), drop = FALSE]}
					}
					if(!is.null(pair_compare_filter_select)){
						if(!is.numeric(pair_compare_filter_select)){
							stop("The parameter pair_compare_filter_select must be numeric !")
						}
						messages_use <- unlist(lapply(as.data.frame(comparisons_list[, pair_compare_filter_select, drop = FALSE]), 
							function(x){paste0(x, collapse = "-")}))
						
						message("Selected groups are ", paste0(messages_use, collapse = " "), " ...")
						comparisons_list %<>% .[, pair_compare_filter_select, drop = FALSE]
					}
				}
				# generate the list
				comparisons_list %<>% {lapply(seq_len(ncol(.)), function(x) .[, x])}
				
				p <- p + ggpubr::stat_compare_means(comparisons = comparisons_list, method = pair_compare_method, 
						tip.length=0.01, label = "p.signif", symnum.args = list(cutpoints = c(0, 0.0001, 0.001, 0.01, 0.05, 1),
						symbols = c("****", "***", "**", "*", "ns")))
			}
			
			p
		},
		#' @description
		#' Plotting clustering result. Require ggdendro package.
		#'
		#' @param use_colors colors for presentation.
		#' @param measure default NULL; beta diversity index; If NULL, using the measure when creating object
		#' @param group default NULL; if provided, use this group to assign color.
		#' @param replace_name default NULL; if provided, use this as label.
		#' @return ggplot.
		#' @examples
		#' t1$plot_clustering(group = "Group", replace_name = c("Saline", "Type"))
		plot_clustering = function(
			use_colors = RColorBrewer::brewer.pal(8, "Dark2"), 
			measure = NULL, 
			group = NULL, 
			replace_name = NULL
			){
			dataset <- self$dataset
			if(is.null(measure)){
				if(is.null(self$use_matrix)){
					measure_matrix <- dataset$beta_diversity[[1]]
					measure <- names(dataset$beta_diversity)[1]
				}else{
					measure_matrix <- self$use_matrix
					measure <- self$measure
				}
			}else{
				measure_matrix <- dataset$beta_diversity[[measure]]
			}
			hc_measure <- hclust(as.dist(measure_matrix))
			hc_d_measure <- ggdendro::dendro_data(as.dendrogram(hc_measure))
			titlename <- switch(measure, wei_unifrac = "Weighted Unifrac", unwei_unifrac = "Unweighted Unifrac", bray = "Bray-Curtis", jaccard = "Jaccard")
			ylabname <- paste0("Distance (", titlename, ")")

			g1 <- ggplot(data = ggdendro::segment(hc_d_measure)) + 
				geom_segment(aes(x=x, y=y, xend=xend, yend=yend), color = "grey30")
			if(!is.null(group) | !is.null(replace_name)){
				data2 <- suppressWarnings(dplyr::left_join(hc_d_measure$label, rownames_to_column(self$sample_table), by = c("label" = "rowname")))
				if(length(replace_name) > 1){
					data2$replace_name_use <- apply(data2[, replace_name], 1, function(x){paste0(x, collapse = "-")})
				}
			}
			if(is.null(group)){
				if(is.null(replace_name)){
					g1 <- g1 + geom_text(data=hc_d_measure$label, aes(x=x, y=y, label=label, hjust=-0.1), size=4)
				}else{
					if(length(replace_name) > 1){
						g1 <- g1 + geom_text(data=data2, aes_string(x="x", y="y", label = "replace_name_use", hjust=-0.1), size=4)
					}else{
						g1 <- g1 + geom_text(data=data2, aes_string(x="x", y="y", label = replace_name, hjust=-0.1), size=4)
					}
				}
			} else {
				if(is.null(replace_name)){
					g1 <- g1 + geom_text(data=data2, aes_string(x="x", y="y", label="label", hjust=-0.1, color = group), size=4)
				}else{
					if(length(replace_name) > 1){
						g1 <- g1 + geom_text(data=data2, aes_string(x="x", y="y", label="replace_name_use", hjust=-0.1, color = group), size=4)
					}else{
						g1 <- g1 + geom_text(data=data2, aes_string(x="x", y="y", label=replace_name, hjust=-0.1, color = group), size=4)
					}
				}
				g1 <- g1 + scale_color_manual(values = use_colors)
			}
			g1 <- g1 + theme(legend.position="none") + coord_flip() +
				scale_x_discrete(labels=ggdendro::label(hc_d_measure)$label) +
				ylab(ylabname) +
				scale_y_reverse(expand=c(0.3, 0)) + 
				xlim(min(ggdendro::segment(hc_d_measure)[,1]) - 0.3, max(ggdendro::segment(hc_d_measure)[,1]) + 0.3) +
				theme(axis.line.y=element_blank(),
					  axis.ticks.y=element_blank(),
					  axis.text.y=element_blank(),
					  axis.title.y=element_blank(),
					  panel.background=element_rect(fill="white"),
					  panel.grid=element_blank(), 
					  panel.border = element_blank()) +
				theme(axis.line.x = element_line(color = "black", linetype = "solid", lineend = "square"))
			g1
		}
		),
	private = list(
		within_group_distance = function(distance, sampleinfo, type){
			all_group <- as.character(sampleinfo[,type]) %>% unique
			res <- list()
			for (i in all_group) {
				res[[i]] <- as.vector(as.dist(distance[sampleinfo[,type] == i, sampleinfo[,type] == i]))
			}
			res <- reshape2::melt(res) 
			colnames(res)[2] <- type
			res
		},
		between_group_distance = function(distance, sampleinfo, type) {
			all_group <- as.character(sampleinfo[,type]) %>% unique
			com1 <- combn(all_group,2)
			res <- list()
			for (i in seq_len(ncol(com1))) {
				f_name <- rownames(sampleinfo[sampleinfo[, type] == com1[1,i], ])
				s_name <- rownames(sampleinfo[sampleinfo[, type] == com1[2,i], ])
				vsname <- paste0(com1[1,i], " vs ", com1[2,i])
				res[[vsname]] <- as.vector(distance[f_name, s_name])
			}
			res <- reshape2::melt(res) 
			colnames(res)[2] <- type
			res
		},
		paired_group_manova = function(sample_info_use, use_matrix, group, measure, p_adjust_method, ...){
			comnames <- c()
			F <- c()
			R2 <- c()
			p_value <- c()
			matrix_total <- use_matrix[rownames(sample_info_use), rownames(sample_info_use)]
			groupvec <- as.character(sample_info_use[ , group])
			all_name <- combn(unique(sample_info_use[ , group]), 2)
			for(i in 1:ncol(all_name)) {
				matrix_compare <- matrix_total[groupvec %in% as.character(all_name[,i]), groupvec %in% as.character(all_name[,i])]
				sample_info_compare <- sample_info_use[groupvec %in% as.character(all_name[,i]), ]
				ad <- adonis2(reformulate(group, substitute(as.dist(matrix_compare))), data = sample_info_compare, ...)
				comnames <- c(comnames, paste0(as.character(all_name[,i]), collapse = " vs "))
				F %<>% c(., ad$F[1])
				R2 %<>% c(., ad$R2[1])
				p_value %<>% c(., ad$`Pr(>F)`[1])
			}
			p_adjusted <- p.adjust(p_value, method = p_adjust_method)
			significance_label <- cut(p_adjusted, breaks = c(-Inf, 0.001, 0.01, 0.05, Inf), label = c("***", "**", "*", ""))
			measure_vec <- rep(measure, length(comnames))
			compare_result <- data.frame(comnames, measure_vec, F, R2, p_value, p_adjusted, significance_label)
			colnames(compare_result) <- c("Groups", "measure", "F", "R2","p.value", "p.adjusted", "Significance")
			compare_result
		}
	),
	lock_class = FALSE,
	lock_objects = FALSE
)
