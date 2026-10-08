export default {
	// R2: komponen dipakai bersama semua pabrik, tanpa usulan/approval (ACTIVE / INACTIVE).
	isNew: true,
	form: { id: null, group_code: '', number: null, name: '', status: 'ACTIVE' },
	formKey: 0,        // naik setiap modal dibuka -> cwKomponenForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwKomponenForm
	similar: [],       // nama mirip (fn_similar_names) untuk teks similarFor
	similarFor: '',
	similarSeq: 0,

	statusOptions: [
		{ label: 'ACTIVE', value: 'ACTIVE' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	canManage() {
		return Auth.can('manage_master');
	},

	canAdd() {
		return this.canManage();
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
		this.similar = [];
		this.similarFor = '';
		this.formKey = this.formKey + 1;
		showModal('mdlKomponen');
	},

	openAdd() {
		// Kelompok awal = filter kelompok di atas tabel (kalau dipilih)
		const code = selKomponenGrup.selectedOptionValue || '';
		this.openForm(true, { id: null, group_code: code, number: code ? this.suggest(code) : null, name: '', status: 'ACTIVE' });
	},

	openEdit(row) {
		this.openForm(false, {
			id: row.id, group_code: row.group_code, number: row.number, name: row.name, status: row.status,
		});
	},

	// cwKomponenForm onSearch: daftar nama mirip ("cari dulu, baru buat")
	async searchSimilar() {
		const text = String((cwKomponenForm.model || {}).similarQuery || '').trim();
		const seq = this.similarSeq + 1;
		this.similarSeq = seq;
		if (text.length < 2) {
			this.similar = [];
			this.similarFor = text;
			return;
		}
		try {
			const rows = await q_similar.run({ kind: 'COMPONENT', text, exclude_id: this.form.id || '' });
			if (seq !== this.similarSeq) return;
			this.similar = rows || [];
			this.similarFor = text;
		} catch (e) {
			/* daftar mirip hanya bantuan — abaikan */
		}
	},

	async save() {
		// Baca model dulu — model di-reset saat state (Default model) berubah
		const m = cwKomponenForm.model || {};
		const data = {
			id: this.form.id,
			group_code: m.group_code,
			number: Number(m.number),
			name: String(m.name || '').trim(),
			status: this.isNew ? 'ACTIVE' : m.status,
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
			this.message = { type: 'error', text: Util.cleanError(msg) };   // aturan nomor / pemakaian dari DB
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlKomponen');
		showAlert(this.isNew ? 'Komponen ditambahkan.' : 'Komponen disimpan.', 'success');
		for (const q of [q_components, q_component_groups]) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
	},
}
