# Show the target slot during itinerary reorder

Status: Ready for review

Branch: `fix/ui`

## Outcome

Option C gives the lifted stop a moving dashed connector and marks the destination with a blue dashed slot. The destination follows the existing reorder calculation.

## Verification

The focused Pocket integration scenario passed on iPhone 18 Pro Simulator (iOS 27.2) with synthetic data. It moved the last stop into the first slot and checked the new stop order. A screenshot captured during the held drag showed the blue dashed connector beside the lifted stop and the outline around the first slot.


## Follow-up: Consistent timeline during lift and drop

The numbered marker and dashed connector keep their resting color and dimensions. The connector moves with the card at a fixed offset, including when a former last stop moves to a position with a following stop. The drop target keeps its blue outline. The lift shadow and driving details fade during the transition.

The focused Pocket UI integration passed on iPhone 18 Pro Simulator (iOS 27.2). Captures taken while holding the drag and after release showed consistent connector geometry and confirmed the last stop moved into the first slot. Result bundle: `/tmp/c67-itinerary-rail-visual.xcresult`.


## Follow-up: Stationary timeline connectors

The connector now belongs to the timeline slot outside the moving row. During a drag, the card carries its original number, while dashed connectors stay in place. The numbers reflect the new order after the drop.

The focused Pocket UI integration passed on iPhone 18 Pro Simulator (iOS 27.2). Captures before and during the drag show stationary connectors and the number moving with its card. Result bundle: `/tmp/c67-itinerary-fixed-rail-final.xcresult`.


## Follow-up: Continuous blue timeline

The approved option B uses blue circles with white numerals and a continuous line behind the rows. The line belongs to the timeline layout. A drag carries the card and its number on top of that line, and the numbers update after the drop.

The focused Pocket UI integration passed on iPhone 18 Pro Simulator (iOS 27.2). Captures before and during the drag showed the same line position while the third stop moved. Result bundle: `/tmp/c67-itinerary-blue-rail.xcresult`.


## Follow-up: Dashed gray timeline

The numbered circles stay blue, and the stationary connector uses a dashed gray stroke. The focused drag-and-drop integration passed on iPhone 18 Pro Simulator (iOS 27.2). Result bundle: `/tmp/c67-itinerary-gray-rail.xcresult`.


## Follow-up: Short connectors between cards

Shortened the gray dashed connectors to 14 points, centered in the gap between cards. They stay in their slots during the drag. The focused drag-and-drop integration passed on iPhone 18 Pro Simulator (iOS 27.2). Result bundle: `/tmp/c67-itinerary-short-rail.xcresult`.


The connector length was increased to 24 points after review. The same focused drag-and-drop integration passed on iPhone 18 Pro Simulator (iOS 27.2). Result bundle: `/tmp/c67-itinerary-24pt-rail.xcresult`.


The connector was then lengthened to 64 points at the default layout, centered between adjacent numbered markers with clearance at each end. The focused integration passed again on iPhone 18 Pro Simulator (iOS 27.2). Result bundle: `/tmp/c67-itinerary-64pt-rail.xcresult`.
