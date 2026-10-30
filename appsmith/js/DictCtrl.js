export default {
	// R21: page Code Dictionary - kamus kode ERP per pabrik, baca saja (izin view_drafts: Vendor Spec, Vendor CBD, Manager Costing).
	// Sub menu Master Material (tombol Code Dictionary di sana, page tersembunyi dari menu samping seperti Material Detail).
	// q_dict mengembalikan paling banyak 200 baris per pencarian; kamus utuh tidak pernah dikirim ke browser.
	// Kode baru masuk kamus lewat Register (source REGISTER); perubahan massal lewat impor Excel (tools/kamus, bukan page ini).
	kindOptions: [
		{ label: 'Material prefix (first 4)', value: 'MATERIAL' },
		{ label: 'Dimension code (middle 3)', value: 'DIMENSION' },
		{ label: 'Color code (last 3)', value: 'COLOR' },
	],

	kind() {
		return selKamusJenis.selectedOptionValue || 'MATERIAL';
	},

	note() {
		return {
			MATERIAL: 'The first 4 characters of a Material Code = one material. App material = the material in this app that uses the prefix.',
			DIMENSION: 'Characters 5-7 of a Material Code = one dimension. (None) = no dimension.',
			COLOR: 'The last 3 characters of a Material Code = one color.',
		}[this.kind()] + ' One code has one meaning. Read only: new codes are added through Register.';
	},

	limitNote() {
		const rows = q_dict.data || [];
		const total = rows.length ? Number(rows[0].total_count) || rows.length : 0;
		return total > rows.length
			? `Showing ${Util.fmtNum(rows.length)} of ${Util.fmtNum(total)} codes. Narrow down with search.` : '';
	},
}
