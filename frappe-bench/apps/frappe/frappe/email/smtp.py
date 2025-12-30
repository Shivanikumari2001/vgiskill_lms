# Copyright (c) 2022, Frappe Technologies Pvt. Ltd. and Contributors
# License: MIT. See LICENSE

import smtplib
import time
from contextlib import suppress

import frappe
from frappe import _
from frappe.email.oauth import Oauth
from frappe.utils import cint, cstr, get_traceback


class InvalidEmailCredentials(frappe.ValidationError):
	pass


class SMTPServer:
	def __init__(
		self,
		server,
		login=None,
		email_account=None,
		password=None,
		port=None,
		use_tls=None,
		use_ssl=None,
		use_oauth=0,
		access_token=None,
	):
		self.login = login
		self.email_account = email_account
		self.password = password
		self._server = server
		self._port = port
		self.use_tls = use_tls
		self.use_ssl = use_ssl
		self.use_oauth = use_oauth
		self.access_token = access_token
		self._session = None

		if not self.server:
			frappe.msgprint(
				_("Email Account not setup. Please create a new Email Account from Settings > Email Account"),
				raise_exception=frappe.OutgoingEmailError,
			)

	@property
	def port(self):
		port = self._port or (self.use_ssl and 465) or (self.use_tls and 587)
		return cint(port)

	@property
	def server(self):
		return cstr(self._server or "")

	def secure_session(self, conn):
		"""Secure the connection incase of TLS."""
		if self.use_tls:
			conn.ehlo()
			conn.starttls()
			conn.ehlo()

	@property
	def session(self):
		"""Get SMTP session.

		We make best effort to revive connection if it's disconnected by checking the connection
		health before returning it to user."""
		if self.is_session_active():
			return self._session

		SMTP = smtplib.SMTP_SSL if self.use_ssl else smtplib.SMTP
		
		# Retry connection up to 3 times with exponential backoff
		max_retries = 3
		last_exception = None
		
		for attempt in range(max_retries):
			_session = None
			try:
				_session = SMTP(self.server, self.port, timeout=2 * 60)
				if not _session:
					raise frappe.OutgoingEmailError(_("Could not connect to outgoing email server"))

				self.secure_session(_session)

				if self.use_oauth:
					Oauth(_session, self.email_account, self.login, self.access_token).connect()

				elif self.password:
					res = _session.login(str(self.login or ""), str(self.password or ""))

					# check if logged correctly
					if res[0] != 235:
						raise frappe.OutgoingEmailError(_("SMTP login failed: {0}").format(res[1]))

				self._session = _session
				self._enqueue_connection_closure()
				return self._session

			except smtplib.SMTPAuthenticationError as e:
				# Authentication errors should not be retried
				last_exception = e
				if _session:
					try:
						_session.quit()
					except Exception:
						pass
				# During validation, allow saving with warning
				# During actual sending, raise exception
				if hasattr(frappe.flags, 'in_email_send') and frappe.flags.in_email_send:
					self.throw_invalid_credentials_exception(email_account=self.email_account)
				else:
					frappe.log_error(
						_("SMTP authentication failed: Invalid credentials"),
						"Email Account SMTP Validation"
					)
					return None
				break

			except (smtplib.SMTPServerDisconnected, smtplib.SMTPException, OSError) as e:
				last_exception = e
				if _session:
					try:
						_session.quit()
					except Exception:
						pass
				
				# If this is the last attempt or during validation, handle accordingly
				if attempt == max_retries - 1:
					# Last attempt failed
					if hasattr(frappe.flags, 'in_email_send') and frappe.flags.in_email_send:
						# During sending, raise exception to trigger retry mechanism in email queue
						raise frappe.OutgoingEmailError(
							_("SMTP connection failed after {0} attempts: {1}").format(max_retries, str(e))
						)
					else:
						# During validation, log and return None to allow saving
						frappe.log_error(
							_("SMTP connection failed: {0}").format(str(e)),
							"Email Account SMTP Validation"
						)
						return None
				else:
					# Wait before retrying (exponential backoff: 1s, 2s, 4s)
					wait_time = 2 ** attempt
					time.sleep(wait_time)
					continue

			except Exception as e:
				last_exception = e
				if _session:
					try:
						_session.quit()
					except Exception:
						pass
				
				# If this is the last attempt or during validation, handle accordingly
				if attempt == max_retries - 1:
					# Last attempt failed
					if hasattr(frappe.flags, 'in_email_send') and frappe.flags.in_email_send:
						# During sending, raise exception to trigger retry mechanism in email queue
						raise frappe.OutgoingEmailError(
							_("SMTP error after {0} attempts: {1}").format(max_retries, str(e))
						)
					else:
						# During validation, log and return None to allow saving
						frappe.log_error(
							_("SMTP validation failed with unexpected error: {0}").format(str(e)),
							"Email Account SMTP Validation"
						)
						return None
				else:
					# Wait before retrying (exponential backoff: 1s, 2s, 4s)
					wait_time = 2 ** attempt
					time.sleep(wait_time)
					continue
		
		# Should not reach here, but just in case
		if last_exception:
			if hasattr(frappe.flags, 'in_email_send') and frappe.flags.in_email_send:
				raise frappe.OutgoingEmailError(
					_("SMTP connection failed: {0}").format(str(last_exception))
				)
			else:
				frappe.log_error(
					_("SMTP connection failed: {0}").format(str(last_exception)),
					"Email Account SMTP Validation"
				)
				return None
		
		return None

	def _enqueue_connection_closure(self):
		if frappe.request and hasattr(frappe.request, "after_response"):
			frappe.request.after_response.add(self.quit)
		elif frappe.job:
			frappe.job.after_job.add(self.quit)
		elif not frappe.flags.in_test:
			# Console?
			import atexit

			atexit.register(self.quit)

	def is_session_active(self):
		if self._session:
			try:
				return self._session.noop()[0] == 250
			except Exception:
				return False

	def quit(self):
		with suppress(TimeoutError):
			if self.is_session_active():
				self._session.quit()

	@classmethod
	def throw_invalid_credentials_exception(cls, email_account=None):
		original_exception = get_traceback() or "\n"
		error_message = (
			_("Please check your email login credentials.") + " " + original_exception.splitlines()[-1]
		)
		error_title = _("Invalid Credentials")
		if email_account:
			error_title = _("Invalid Credentials for Email Account: {0}").format(email_account)

		frappe.throw(
			error_message,
			title=error_title,
			exc=InvalidEmailCredentials,
		)
