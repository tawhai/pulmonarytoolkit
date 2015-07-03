classdef PTKListBox < PTKPanel
    % PTKListBox. A panel containing a list of selectable items.
    %
    %     PTKListBox represents a panel of selectable items. PTKListBox is a fixed
    %     size; use PTKSlidingListBox for a scrolling list box.
    %
    %     Licence
    %     -------
    %     Part of the TD Pulmonary Toolkit. https://github.com/tomdoel/pulmonarytoolkit
    %     Author: Tom Doel, 2014.  www.tomdoel.com
    %     Distributed under the GNU GPL v3 licence. Please see website for details.
    %    
        
    properties (SetAccess = private)
        SelectedTag
    end
    
    properties (Access = private)
        Items
        LowerYPosition
    end
    
    properties
        TopMargin = 5
        BottomMargin = 5
        SpacingBetweenItems = 5
        LeftMargin = 5
        RightMargin = 5
    end
    
    methods
        function obj = PTKListBox(parent, reporting)            
            obj = obj@PTKPanel(parent, reporting);
            obj.Enabled = true;
        end
        
        function CreateGuiComponent(obj, position, reporting)
            CreateGuiComponent@PTKPanel(obj, position, reporting);
            
            % A series may already have been selected
            if ~isempty(obj.SelectedTag)
                obj.SelectItem(obj.SelectedTag, true);
            end
        end
        
        function Resize(obj, new_position)
            Resize@PTKPanel(obj, new_position);
            height = obj.GetRequestedHeight(0);
            obj.LowerYPosition = height - obj.TopMargin;
            width = new_position(3) - obj.LeftMargin - obj.RightMargin;
            for item_index = 1 : numel(obj.Items)
                text_height = obj.Items(item_index).TextHeight;
                obj.LowerYPosition = obj.LowerYPosition - text_height;
                item_location = [obj.LeftMargin, obj.LowerYPosition, width, text_height];
                obj.Items(item_index).Resize(item_location);
                
                % Determine if current panel is visible
                item_is_visible = (item_location(2) < new_position(4) && ((item_location(2) + item_location(4)) >= -new_position(2)));
                if item_is_visible
                    obj.Items(item_index).Enable(obj.Reporting);
                else
                    obj.Items(item_index).Disable;
                end
                
                obj.LowerYPosition = obj.LowerYPosition - obj.SpacingBetweenItems;
                
            end
        end
        
        function height = GetRequestedHeight(obj, width)
            height = obj.TopMargin + obj.BottomMargin;
            for item = obj.Items
                height = height + item.TextHeight;
            end
            height = height + max(0, numel(obj.Items) - 1)*obj.SpacingBetweenItems;
        end
        
        function [min_y, max_y] = GetYPositionForItem(obj, tag)
            for item_index = 1 : numel(obj.Items)
                item = obj.Items(item_index);
                if strcmp(item.Tag, tag)
                    if isempty(item.Position)
                        min_y = [];
                        max_y = [];
                    else
                        min_y = item.Position(2);
                        max_y = item.Position(2) + item.Position(4);
                    end
                    return;
                end
            end
            min_y = [];
            max_y = [];
        end
        
        function SelectItem(obj, tag, selected)

            obj.Deselect;
            if selected
                obj.SelectedTag = tag;
            else
                obj.SelectedTag = [];
            end
            
            item_found = false;
            for item_index = 1 : numel(obj.Items)
                item = obj.Items(item_index);
                if strcmp(item.Tag, tag)
                    item.Select(selected);
                    item_found = true;
                end
            end
            
            if ~item_found
                obj.SelectedTag = [];
            end
        end

        function ClearItems(obj)
            obj.RemoveAndDeleteChildren;
            obj.Items = [];
            obj.SelectedTag = [];
        end

        function AddItem(obj, item)
            item_index = numel(obj.Items) + 1;
            if isempty(obj.Items)
                obj.Items = item;
            else
                obj.Items(item_index) = item;
            end
            
            
            text_height = item.TextHeight;
            obj.LowerYPosition = obj.LowerYPosition - text_height;
            if ~isempty(obj.Position)
                item_location = [1, obj.LowerYPosition, obj.Position(3), text_height];
                item.Resize(item_location);
            end
            
            obj.AddChild(item, obj.Reporting);
        end
        
        function Deselect(obj)
            % Unselect old item
            if ~isempty(obj.SelectedTag)
                for item_index = 1 : numel(obj.Items)
                    item = obj.Items(item_index);
                    if strcmp(item.Tag, obj.SelectedTag)
                        item.Select(false);
                    end
                end
            end
            obj.SelectedTag = [];
        end
        
    end
    
end