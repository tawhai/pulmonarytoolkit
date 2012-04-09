function results = TDAirwayRegionGrowingWithExplosionControl(threshold_image, start_point, maximum_number_of_generations, explosion_multiplier, reporting)
    % TDAirwayRegionGrowingWithExplosionControl. Segments the airways from a
    %     threshold image using a region growing method.
    %
    %     Given a binary image which representes an airway threshold applied to
    %     a lung CT image, TDAirwayRegionGrowingWithExplosionControl finds a
    %     tree structure representing the bifurcating airway tree. Airway
    %     segmentation proceeds by wavefront growing and splitting, with
    %     heuristics to prevent 'explosions' into the lung parenchyma.
    %
    % Syntax:
    %     results = TDAirwayRegionGrowingWithExplosionControl(threshold_image, start_point, reporting)
    %
    % Inputs:
    %     threshold_image - a lung volume stored as a TDImage which has been
    %         thresholded for air voxels (1=air, 0=background).
    %         Note: the lung volume can be a region-of-interest, or the entire
    %         volume.
    %
    %     start_point - coordinate (i,j,k) of a point inside and near the top
    %         of the trachea (as returned by plugin TDTopOfTrachea)
    %
    %     maximum_number_of_generations - tree-growing will terminate for each
    %         branch when it exceeds this number of generations in that branch
    %
    %     explosion_multiplier - 7 is a typical value. An explosion is detected
    %         when the number of new voxels in a wavefront exceeds the previous
    %         minimum by a factor defined by this parameter
    %
    %     reporting (optional) - an object implementing the TDReporting
    %         interface for reporting progress and warnings
    %
    % Outputs:
    %     results - a structure containing the following fields:
    %         airway_tree - a TDTreeSegment object which represents the trachea.
    %             This is linked to its child segments via its Children
    %             property, and so on, so the entre tree can be accessed from
    %             this property.
    %         explosion_points - Indices of all voxels which were marked as
    %             explosions during the region-growing process.
    %         endpoints - Indices of final points in each
    %             branch of the airway tree
    %         start_point - the trachea location as passed into the function
    %         image_size - the image size
    %
    % See the TDAirways plugin for an example of how to reconstruct this results
    % structure into an image
    %
    %
    %     Licence
    %     -------
    %     Part of the TD Pulmonary Toolkit. http://code.google.com/p/pulmonarytoolkit
    %     Author: Tom Doel, 2012.  www.tomdoel.com
    %     Distributed under the GNU GPL v3 licence. Please see website for details.
    %
    
    if ~isa(threshold_image, 'TDImage')
        reporting.Error('TDAirwayRegionGrowingWithExplosionControl:InvalidInput', 'Requires a TDImage as input');
    end

    reporting.UpdateProgressMessage('Starting region growing with explosion control');
    
    % Perform the airway segmentation
    airway_tree = RegionGrowing(threshold_image, start_point, reporting, maximum_number_of_generations, explosion_multiplier);

    
    if isempty(airway_tree)
        reporting.ShowWarning('TDRobustRegionGrowingWithExplosionControl:AirwaySegmentationFailed', 'Airway segmentation failed', []);
    else
        % Sanity checking and warn user if any branches terminated early
        CheckSegments(airway_tree, reporting);
        
        % Find points which indicate explosions
        explosion_points = GetExplosionPoints(airway_tree);
        
        % Remove segments in which all points are marked as explosions
        airway_tree = RemoveCompletelyExplodedSegments(airway_tree);
        
        % Remove holes within the airway segments
        reporting.ShowProgress('Closing airways segmentally');
        closing_size_mm = 5;
        airway_tree = TDCloseBranchesInTree(airway_tree, closing_size_mm, threshold_image.ImageSize, reporting);

        % Find and store endpoints
        reporting.ShowProgress('Finding endpoints');
        endpoints = FindEndpointsInAirwayTree(airway_tree);

        % Store the results
        results = [];
        results.explosion_points = explosion_points;
        results.endpoints = endpoints;
        results.airway_tree = airway_tree;
        results.start_point = start_point;
        results.image_size = threshold_image.ImageSize;
    end
    
end


function first_segment = RegionGrowing(threshold_image, start_point, reporting, maximum_number_of_generations, explosion_multiplier)
    
    voxel_size_mm = threshold_image.VoxelSize;
    
    min_distance_before_bifurcating_mm = max(3, ceil(threshold_image.ImageSize(3)*voxel_size_mm(3))/4);

    start_point = int32(start_point);
    image_size = int32(threshold_image.ImageSize);
    
    threshold_image = logical(threshold_image.RawImage);
    number_of_image_points = numel(threshold_image(:));
        
    [linear_offsets, ~] = TDImageCoordinateUtilities.GetLinearOffsets(size(threshold_image));
    
    first_segment = TDTreeSegment([], min_distance_before_bifurcating_mm, voxel_size_mm, maximum_number_of_generations, explosion_multiplier);
    start_point_index = sub2ind(image_size, start_point(1), start_point(2), start_point(3));
    
    threshold_image(start_point_index) = false;
    
    segments_in_progress = first_segment.AddNewVoxelsAndGetNewSegments(start_point_index, image_size);
        
    while ~isempty(segments_in_progress)
        
        if reporting.HasBeenCancelled
            reporting.Error('TDAirwayRegionGrowingWithExplosionControl:UserCancel', 'User cancelled');
        end
        
        % Get the next airway segment to add voxels to
        current_segment = segments_in_progress{end};
        segments_in_progress(end) = [];
        
        % Fetch the front of the wavefront for this segment
        frontmost_points = current_segment.GetFrontmostPoints;
        
        % Find the neighbours of these points, which will form the next 
        % generation of points to add to the wavefront
        indices_of_new_points = GetNeighbouringPoints(frontmost_points', linear_offsets);
        indices_of_new_points = indices_of_new_points(indices_of_new_points > 0 & indices_of_new_points <= number_of_image_points);
        indices_of_new_points = indices_of_new_points(threshold_image(indices_of_new_points))';
        threshold_image(indices_of_new_points) = false;

                
        % Add points to the current segment and retrieve a list of segments
        % which reqire further processing - this can comprise of the current
        % segment if it is incomplete, or child segments if it has bifurcated
        if isempty(indices_of_new_points)
            current_segment.CompleteThisSegment;
        else
            next_segments = current_segment.AddNewVoxelsAndGetNewSegments(indices_of_new_points, image_size);
            segments_in_progress = [segments_in_progress, next_segments]; %#ok<AGROW>
            if length(segments_in_progress) > 500
               reporting.Error('TDAirwayRegionGrowingWithExplosionControl:MaximumSegmentsExceeded', 'More than 500 segments to do: is there a problem with the image?'); 
            end
        end
    end
end

function explosion_points = GetExplosionPoints(processed_segments)
    explosion_points = [];
    segments_to_do = processed_segments;
    while ~isempty(segments_to_do)
        next_segment = segments_to_do(1);
        segments_to_do(1) = [];
        explosion_points = cat(2, explosion_points, next_segment.GetExplodedVoxels);
        segments_to_do = [segments_to_do, next_segment.Children]; %#ok<AGROW>
    end
end

% Check the segments have completed correctly, and warn the user if some
% branches terminated early
function CheckSegments(airway_tree, reporting)
    number_of_branches_with_exceeded_generations = 0;
    segments_to_do = airway_tree;
    while ~isempty(segments_to_do)
        next_segment = segments_to_do(1);
        if next_segment.ExceededMaximumNumberOfGenerations
            number_of_branches_with_exceeded_generations = number_of_branches_with_exceeded_generations + 1;
        end
        segments_to_do(1) = [];
        wavefront = next_segment.WavefrontIndices;
        if ~isempty(wavefront)
            reporting.Error('TDAirwayRegionGrowingWithExplosionControl:NonEmptyWavefront', 'Program error: Wavefront is not empty when it should be.');
        end
        segments_to_do = [segments_to_do, next_segment.Children]; %#ok<AGROW>
    end
    
    if number_of_branches_with_exceeded_generations > 0
        if number_of_branches_with_exceeded_generations == 1
            loop_text = 'branch has';
        else
            loop_text = 'branches have';
        end
        reporting.ShowWarning('TDProcessAirwaySkeleton:InternalLoopRemoved', [num2str(number_of_branches_with_exceeded_generations) ...
            ' airway ' loop_text ' been terminated because the maximum number of airway generations has been exceeded. This may indicate that the airway has leaked into the surrounding parenchyma.'], []);
    end
    
end

function list_of_point_indices = GetNeighbouringPoints(point_indices, linear_offsets)
    if isempty(point_indices)
        list_of_point_indices = [];
        return
    end
    
    list_of_point_indices = repmat(int32(point_indices), 1, 6) + repmat(int32(linear_offsets), length(point_indices), 1);    
    list_of_point_indices = unique(list_of_point_indices(:));
    
end
    


function airway_tree = RemoveCompletelyExplodedSegments(airway_tree)
    segments_to_do = airway_tree;
    while ~isempty(segments_to_do)
        next_segment = segments_to_do(1);
        segments_to_do(1) = [];
        
        if numel(next_segment.GetAcceptedVoxels) == 0
            parent = next_segment.Parent;
            if ~isempty(parent)
                children = next_segment.Children;
                parent.Children = setdiff(parent.Children, next_segment);
                parent.Children = [parent.Children, children];
            end
        end
        segments_to_do = [segments_to_do, next_segment.Children];
    end
    airway_tree.RecomputeGenerations(1);
end

function endpoints = FindEndpointsInAirwayTree(airway_tree, reporting)
    endpoints = [];

    segments_to_do = airway_tree;
    while ~isempty(segments_to_do)
        segment = segments_to_do(end);
        segments_to_do(end) = [];
        segments_to_do = [segments_to_do, segment.Children];

        if isempty(segment.Children)
            final_voxels_in_segment = segment.AcceptedIndicesOK{end};
            if isempty(final_voxels_in_segment)
                reporting.Error('TDAirwayRegionGrowingWithExplosionControl:NoAcceptedIndices', 'No accepted indices in this airway segment');
            end
            endpoints(end + 1) = final_voxels_in_segment(end);
        end        
    end
end

