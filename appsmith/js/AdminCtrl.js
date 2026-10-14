export default {
	// Page Admin. Form user: cwUserForm, pabrik: cwFactoryForm, password sementara: cwTempPassword.
	isNew: true,
	form: { email: '', full_name: '', role: 'VENDOR_SPEC', is_active: true, factory_id: '' },
	formKey: 0,        // naik setiap modal dibuka -> cwUserForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwUserForm

	// Password sementara terakhir (ditampilkan sekali di mdlPasswordSementara)
	tempPassword: '',
	tempFor: '',

	roleOptions: [
		{ label: 'Vendor - Specsheet', value: 'VENDOR_SPEC' },
		{ label: 'Vendor - CBD', value: 'VENDOR_CBD' },
		{ label: 'Manager Costing', value: 'MANAGER_COSTING' },
		{ label: 'Brand Viewer', value: 'BRAND_VIEWER' },
		{ label: 'System Admin', value: 'SYSTEM_ADMIN' },
	],

	// Role yang wajib menempel ke satu pabrik (R1, keputusan user 8 Okt 2026)
	factoryRoles: ['VENDOR_SPEC', 'VENDOR_CBD', 'MANAGER_COSTING'],

	// Pilihan pabrik di form user: pabrik aktif + pabrik user yang sedang diubah (walau sudah nonaktif)
	factoryOptions() {
		const current = this.form.factory_id;
		return (q_factories.data || [])
			.filter(f => f.status === 'ACTIVE' || f.id === current)
			.map(f => ({ label: f.status === 'ACTIVE' ? f.name : `${f.name} (inactive)`, value: f.id }));
	},

	openForm(isNew, form) {
		this.isNew = isNew;
		this.form = form;
		this.busy = false;
		this.message = null;
		this.formKey = this.formKey + 1;
		showModal('mdlUser');
	},

	openAdd() {
		this.openForm(true, { email: '', full_name: '', role: 'VENDOR_SPEC', is_active: true, factory_id: '' });
	},

	openEdit(row) {
		this.openForm(false, {
			email: row.email, full_name: row.full_name, role: row.role, is_active: row.is_active,
			factory_id: row.factory_id || '',
		});
	},

	async save() {
		// Baca model dulu - model di-reset saat state (Default model) berubah
		const m = cwUserForm.model || {};
		const needsFactory = this.factoryRoles.includes(m.role);
		const data = {
			email: String(m.email || '').trim().toLowerCase(),
			full_name: String(m.full_name || '').trim(),
			role: m.role,
			is_active: m.is_active !== false,
			is_new: this.isNew,
			factory_id: needsFactory ? (m.factory_id || '') : '',
		};
		if (!data.email || !data.full_name || !data.role) {
			this.message = { type: 'error', text: 'Fill in email, name, and role.' };
			return;
		}
		if (needsFactory && !data.factory_id) {
			this.message = { type: 'error', text: 'This role needs a factory.' };
			return;
		}
		this.message = null;
		this.busy = true;
		try {
			await a_user_save.run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlUser');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlUser');
		showAlert('User saved.', 'success');
		for (const q of [q_users, q_factories, q_audit, q_audit_entities]) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
		const pass = a_user_save.data && a_user_save.data[0] && a_user_save.data[0].temp_password;
		if (pass) this.showTempPassword(data.email, pass);
	},

	// Query a_user_reset_password memakai "Request confirmation before running" = ON
	async resetPassword(row) {
		const ok = await Util.run(a_user_reset_password, { email: row.email }, 'Password reset.', [q_users, q_audit]);
		if (!ok) return;
		const pass = a_user_reset_password.data && a_user_reset_password.data[0]
			&& a_user_reset_password.data[0].temp_password;
		if (pass) this.showTempPassword(row.email, pass);
	},

	showTempPassword(email, pass) {
		this.tempFor = email;
		this.tempPassword = pass;
		showModal('mdlPasswordSementara');
	},

	closeTempPassword() {
		this.tempPassword = '';
		this.tempFor = '';
		closeModal('mdlPasswordSementara');
	},

	userStatus(row) {
		if (!row.is_active) return 'Inactive';
		if (row.locked_until && moment(row.locked_until).isAfter(moment())) return 'Locked';
		if (row.must_change_password) return 'Must change password';
		return 'Active';
	},

	// ---- R14: detail audit (panel cwAuditDetail di sebelah tblAudit, mengikuti baris terpilih) ----
	// UPDATE: kolom yang berubah saja · INSERT: isi bila tersimpan (audit ramping R11 tidak menyimpan isi) ·
	// DELETE: isi lengkap. Kolom teknis dipisah (bisa dibuka di panel); kunci rahasia tidak pernah tampil
	// (juga dibuang di q_audit).
	auditTechKeys: ['id', 'created_at', 'created_by', 'updated_at', 'updated_by'],
	auditSecret: 'password|token|secret|hash',   // pola kunci rahasia (sama dengan q_audit)
	auditMaxLen: 160,

	auditModel(id) {
		const row = (q_audit.data || []).find(r => String(r.id) === String(id));
		if (!row) return { empty: true };
		const before = this.auditJson(row.before_data);
		const after = this.auditJson(row.after_data);
		const action = String(row.action || '');
		let keys = [...new Set([...Object.keys(before || {}), ...Object.keys(after || {})])];
		if (action === 'UPDATE' && before && after) {
			keys = keys.filter(k => JSON.stringify(before[k]) !== JSON.stringify(after[k]));
		}
		const secret = new RegExp(this.auditSecret, 'i');
		keys = keys.filter(k => !secret.test(k)).sort();
		const kind = action === 'UPDATE' ? 'diff' : action === 'DELETE' ? 'before' : action === 'INSERT' ? 'after' : 'diff';
		const rows = keys.map(k => ({
			field: k,
			tech: this.auditTechKeys.includes(k),
			before: kind === 'after' ? null : this.auditValue(before ? before[k] : null),
			after: kind === 'before' ? null : this.auditValue(after ? after[k] : null),
		}));
		let note = '';
		if (!rows.length) {
			note = action === 'INSERT' ? 'Record created. New records are not copied to the audit log.'
				: action === 'UPDATE' ? 'No changed fields recorded.'
					: 'No data recorded for this action.';
		}
		return {
			empty: false,
			key: row.id,
			action,
			entity: row.entity || '-',
			entityId: row.entity_id || '-',
			time: row.created_at ? moment(row.created_at).utcOffset(7).format('DD MMM YYYY, HH:mm:ss') + ' WIB' : '-',
			user: row.user_email || '-',
			kind,
			title: { UPDATE: 'Changed fields', DELETE: 'Deleted record', INSERT: 'Created record' }[action] || 'Data',
			note,
			rows,
		};
	},

	// jsonb bisa datang sebagai objek atau teks
	auditJson(v) {
		if (v === null || v === undefined || v === '') return null;
		if (typeof v === 'object') return v;
		try { return JSON.parse(v); } catch (e) { return { value: String(v) }; }
	},

	// { text, full, empty }: uuid diringkas 8 karakter, waktu ke WIB, teks panjang dipotong (full = untuk tooltip)
	auditValue(v) {
		if (v === null || v === undefined || v === '') return { text: '(empty)', full: '', empty: true };
		const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
		if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s)) {
			return { text: s.slice(0, 8) + '…', full: s, empty: false };
		}
		if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(s)) {
			return { text: moment(s).utcOffset(7).format('DD MMM YYYY, HH:mm:ss') + ' WIB', full: s, empty: false };
		}
		if (s.length > this.auditMaxLen) {
			return { text: s.slice(0, this.auditMaxLen) + '…', full: s.slice(0, 2000), empty: false };
		}
		return { text: s, full: '', empty: false };
	},

	// ---- Pabrik (tab Pabrik, modal mdlPabrik) ----
	factoryForm: { id: '', name: '', status: 'ACTIVE' },
	factoryKey: 0,
	factoryBusy: false,
	factoryMessage: null,

	openFactory(form) {
		this.factoryForm = form;
		this.factoryBusy = false;
		this.factoryMessage = null;
		this.factoryKey = this.factoryKey + 1;
		showModal('mdlPabrik');
	},

	openFactoryAdd() {
		this.openFactory({ id: '', name: '', status: 'ACTIVE' });
	},

	openFactoryEdit(row) {
		this.openFactory({ id: row.id, name: row.name, status: row.status });
	},

	async saveFactory() {
		const m = cwFactoryForm.model || {};
		const data = {
			id: this.factoryForm.id || '',
			name: String(m.name || '').trim(),
			status: m.status || 'ACTIVE',
		};
		if (!data.name) {
			this.factoryMessage = { type: 'error', text: 'Factory name is required.' };
			return;
		}
		this.factoryMessage = null;
		this.factoryBusy = true;
		try {
			await a_factory_save.run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlPabrik');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.factoryMessage = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.factoryBusy = false;
		}
		closeModal('mdlPabrik');
		showAlert('Factory saved.', 'success');
		for (const q of [q_factories, q_users, q_audit, q_audit_entities]) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
	},
}
