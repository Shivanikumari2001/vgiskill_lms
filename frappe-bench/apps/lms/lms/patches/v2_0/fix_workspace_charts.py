"""Fix LMS workspace by removing charts that break the UI"""

import frappe
import json


def execute():
	"""Remove charts from LMS workspace and content to prevent UI breakage"""
	try:
		if not frappe.db.exists("Workspace", "LMS"):
			return
		
		workspace = frappe.get_doc("Workspace", "LMS")
		changed = False
		
		# Remove all charts from charts array
		if workspace.charts:
			workspace.charts = []
			changed = True
		
		# Remove chart blocks from content
		if workspace.content:
			try:
				content_blocks = json.loads(workspace.content)
				original_count = len(content_blocks)
				# Filter out chart blocks
				content_blocks = [b for b in content_blocks if b.get("type") != "chart"]
				if len(content_blocks) < original_count:
					workspace.content = json.dumps(content_blocks)
					changed = True
			except (json.JSONDecodeError, TypeError):
				pass
		
		if changed:
			workspace.save(ignore_permissions=True)
			frappe.db.commit()
	except Exception as e:
		frappe.log_error(f"Error fixing LMS workspace charts: {e}", "Workspace Fix")

