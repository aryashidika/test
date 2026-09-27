// JSObject "KomponenCtrl" — page Master Komponen. Form: Custom Widget cwKomponenForm di modal mdlKomponen.
// Tambah: Master Admin -> APPROVED, vendor (propose_master) -> PROPOSED (ditentukan fn_component_add).
// Ubah, ubah status, Approve: hanya Master Admin (manage_master).
export default {
	isNew: true,
	form: { id: null, group_code: '', number: null, name: '', status: 'APPROVED' },
	formKey: 0,        // naik setiap modal dibuka -> cwKomponenForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwKomponenForm

	statusOptions: [
		{ label: 'APPROVED', value: 'APPROVED' },
		{ label: 'PROPOSED', value: 'PROPOSED' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	canManage() {
		return Auth.can('manage_master');
	},

	canAdd() {
		return Auth.can('manage_master') || Auth.can('propose_master');
	},

	// Dipakai cwKomponenForm: { code, name, range_start, range_end, next_no }
	groups() {
		return q_component_groups.data || [];
	},

	// Opsi filter kelompok di atas tabel: "a — Upper (0–3990)"
	groupOptions() {
		return this.groups().map(g => ({
			label: `${g.code} — ${g.name} (${g.range_start}–${g.range_end})`,
			value: g.code,
		}));
	},

	suggest(code) {
		const g = this.groups().find(x => x.code === code);
		return g ? g.next_no : null;
	},

	openForm(isNew, form) {
		this.isNew = isNew;
		this.form = form;
		this.busy = false;
		this.message = null;
		this.formKey = this.formKey + 1;
		showModal('mdlKomponen');
	},

	openAdd() {
		// Kelompok awal = filter kelompok di atas tabel (kalau dipilih)
		const code = selKomponenGrup.selectedOptionValue || '';
		this.openForm(true, { id: null, group_code: code, number: code ? this.suggest(code) : null, name: '', status: 'APPROVED' });
	},

	openEdit(row) {
		this.openForm(false, {
			id: row.id, group_code: row.group_code, number: row.number, name: row.name, status: row.status,
		});
	},

	async save() {
		// Baca model dulu — model di-reset saat state (Default model) berubah
		const m = cwKomponenForm.model || {};
		const data = {
			id: this.form.id,
			group_code: m.group_code,
			number: Number(m.number),
			name: String(m.name || '').trim(),
			status: m.status,
		};
		if (!data.group_code || !data.name || !Number.isInteger(data.number)) {
			this.message = { type: 'error', text: 'Lengkapi kelompok, nomor, dan nama komponen.' };
			return;
		}
		this.message = null;
		this.busy = true;
		try {
			await (this.isNew ? a_component_add : a_component_update).run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlKomponen');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };   // aturan nomor dari DB
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlKomponen');
		showAlert(!this.isNew ? 'Komponen disimpan.'
			: this.canManage() ? 'Komponen ditambahkan.'
			: 'Usulan komponen terkirim (PROPOSED), menunggu persetujuan Master Admin.', 'success');
		for (const q of [q_components, q_component_groups]) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
	},

	approve(row) {
		return Util.run(a_component_set_status, { id: row.id, status: 'APPROVED' },
			`Komponen ${row.number} disetujui.`, [q_components]);
	},
}
