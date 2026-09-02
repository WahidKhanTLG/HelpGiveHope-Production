import { LightningElement, track, wire, api } from 'lwc';
import getZoneOptions from '@salesforce/apex/InterviewDayUiHelper.getZoneOptions';
import getYearOptions from '@salesforce/apex/InterviewDayUiHelper.getYearOptions';
import getScheduleYearSummary from '@salesforce/apex/InterviewDayUiHelper.getScheduleYearSummary';
import ensureScheduleYear from '@salesforce/apex/InterviewDayUiHelper.ensureScheduleYear';
import previewScheduleDates from '@salesforce/apex/InterviewDayUiHelper.preview';
import generate from '@salesforce/apex/InterviewDayUiHelper.generate';
import generateWithOverrides from '@salesforce/apex/InterviewDayUiHelper.generateWithOverrides';
import deleteScheduleDatesWithOverrides from '@salesforce/apex/InterviewDayUiHelper.deleteScheduleDatesWithOverrides';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Import methods from InterviewDayUiHelper for placeholder functionality
import getScheduleDatesForZone from '@salesforce/apex/InterviewDayUiHelper.getScheduleDatesForZone';
import processPlaceholdersByDates from '@salesforce/apex/InterviewDayUiHelper.processPlaceholdersByDates';
import getExistingInterviewDays from '@salesforce/apex/InterviewDayUiHelper.getExistingInterviewDays';
import deleteSelectedInterviewSchedules from '@salesforce/apex/InterviewDayUiHelper.deleteSelectedInterviewSchedules';

// Import utility functions
import { buildRuleText, getActionClass } from './dateUtils';
import { refreshApex } from '@salesforce/apex';

export default class GenerateInterviewDates extends LightningElement {
  // Component properties
  @api title = 'Interview Date Generator';

  // Shared properties
  @track currentTab = 'dates'; // 'dates' or 'placeholders'
  @track zoneSummaries = []; // For displaying zone-specific data in the new format
  
  // Year control state
  @track year = new Date().getFullYear() + 1; // resolved numeric year used by services
  @track yearOption = String(new Date().getFullYear() + 1); // combobox value: '2025' | '2026' | 'CUSTOM'
  @track yearOptions = [];
  @track customYear = '';
  @track showCustomYear = false;
  @track yearBanner = '';
  @track zoneOptions = [];
  @track selectedZones = [];
  
  // Wired properties
  wiredZoneOptions;
  wiredYearOptions;
  @track action = 'CREATE_NEW';
  @track rows = [];
  @track busy = false;
  @track disableGenerate = true;
  @track disableDelete = true;
  @track counts = { create: 0, update: 0, skip: 0 };
  @track draftValues = [];
  @track selectedKeys = new Set();
  @track hasPreviewEdits = false;
  @track expandedZones = new Set();
  @track expectedRecordCount = 0;
  @track showGenerateSection = true;
  @track showCompactLayout = true; // Flag to enable/disable compact layout
  @track debugView = false; // toggles the two-column debug table
  @track zoneFilter = 'ALL'; // filter to a single zone name or ALL

  // Preview list removed (was unused in template)

  // Delete modal state
  @track showDeleteModal = false;
  @track deleteConfirmationText = '';
  
  // ========= PLACEHOLDER GENERATION PROPERTIES =========
  @track selectedZoneId = '';
  @track selectedMode = '';
  @track selectedSlots = '';
  @track dateOptions = [];
  @track selectedDateIds = [];
  @track selectedUniqueDates = []; 
  @track lastGeneratedSummary = '';
  @track showPlaceholderSection = false;
  @track showExistingPlaceholderRows = false;
  @track selectedPlaceholderScheduleIds = [];
  
  // Wire existing interview days for placeholder section
  @wire(getExistingInterviewDays)
  wiredExistingInterviewDays;

  // Unique icons for each zone
  zoneIcons = {
    'Zone 1': 'custom:custom74', // Mountain icon
    'Zone 2': 'custom:custom75', // Forest icon  
    'Zone 3': 'custom:custom76', // River icon
    'Zone 4': 'custom:custom77', // Desert icon
    'Zone 5': 'custom:custom78', // City icon
    'Zone 6': 'custom:custom79', // Coastal icon
    // Fallback icons if custom icons aren't available
    'default1': 'standard:location',
    'default2': 'standard:groups',
    'default3': 'standard:places',
    'default4': 'standard:territory',
    'default5': 'standard:address',
    'default6': 'standard:record'
  };

  // Removed actionOptions (no UI uses it)

  // Columns for zone-grouped view (no Zone column since it's in the header)
  zoneColumns = [
    { 
      label: 'Recurrence Rule', 
      fieldName: 'rule', 
      type: 'text',
      wrapText: true
    },
    { 
      label: 'Scheduled Date', 
      fieldName: 'calculatedDate', 
      type: 'date',
      editable: true,
      typeAttributes: {
        year: 'numeric',
        month: 'short',
        day: '2-digit'
      }
    },
    { 
      label: 'Action', 
      fieldName: 'action', 
      type: 'text',
      cellAttributes: { 
        class: { fieldName: 'actionClass' }
      }
    },
    {
      label: 'Delete Status',
      fieldName: 'deleteStatusLabel',
      type: 'text',
      wrapText: true,
      cellAttributes: {
        class: { fieldName: 'deleteStatusClass' }
      }
    }
  ];

  // Removed unused 'columns' config (we use zoneColumns and debugColumns)

  // Columns for debug view: exactly two columns as requested
  debugColumns = [
    { label: 'Rule', fieldName: 'rule', type: 'text', wrapText: true },
    { label: 'Calculated Date', fieldName: 'calculatedDate', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } }
  ];

  existingPlaceholderColumns = [
    { label: 'Schedule Id', fieldName: 'recordId', type: 'text', initialWidth: 210 },
    { label: 'Zone', fieldName: 'zoneName', type: 'text' },
    {
      label: 'Interview Date',
      fieldName: 'interviewDate',
      type: 'date',
      typeAttributes: {
        year: 'numeric',
        month: 'short',
        day: '2-digit'
      }
    },
    { label: 'Mode', fieldName: 'scheduleMode', type: 'text' },
    { label: 'Placeholder Slot', fieldName: 'scheduleName', type: 'text', wrapText: true },
    { label: 'Booked', fieldName: 'booked', type: 'boolean' },
    { label: 'Delete Eligible', fieldName: 'isDeleteEligible', type: 'boolean' },
    { label: 'Status', fieldName: 'status', type: 'text' }
  ];

  // Wire zone options
  @wire(getZoneOptions)
  wiredZoneOptionsHandler(result) {
    this.wiredZoneOptions = result;
    if (result.data) {
      const opts = result.data;
      this.zoneOptions = opts.map((o, index) => ({ 
        label: o.label, 
        value: o.value, 
        selected: false,
        iconName: this.getZoneIcon(o.label, index),
        tileClass: 'zone-tile',
        iconVariant: 'default',
        hasExistingRecords: false,
        disabled: false
      }));
      
      // Check for existing records if year is already set
      if (this.year) {
        this.checkExistingRecords();
      }
    } else if (result.error) {
      this.toast(this.err(result.error), 'error');
    }
  }
  
  // Wire year options
  @wire(getYearOptions)
  wiredYearOptionsHandler(result) {
    this.wiredYearOptions = result;
    if (result.data) {
      const list = result.data;
      const serverYears = (list || []).map(o => ({ label: o.label, value: o.value }));
      // Always include our presets and Custom…
      const presets = [
        { label: '2025', value: '2025' },
        { label: '2026', value: '2026' }
      ];
      const combined = new Map();
      [...presets, ...serverYears].forEach(o => combined.set(o.value, o));
      const opts = Array.from(combined.values()).sort((a,b)=>b.value.localeCompare(a.value));
      opts.push({ label: 'Custom…', value: 'CUSTOM' });
      this.yearOptions = opts;
      const y = String(this.year);
      this.yearOption = opts.some(o=>o.value===y) ? y : 'CUSTOM';
      this.showCustomYear = this.yearOption === 'CUSTOM';
      if (this.showCustomYear) this.customYear = y;
    } else if (result.error) {
      this.toast(this.err(result.error), 'error');
    }
  }

  connectedCallback() {
    this.refreshYearBanner();
    this.recomputeDisableGenerate();
  }

  async checkExistingRecords() {
    try {
      // Get summary to check which zones have existing records
      const summary = await getScheduleYearSummary({ year: this.year });
      const zoneSummaries = Array.isArray(summary?.byZone) ? summary.byZone : [];
      const zonesWithRecords = new Set(
        zoneSummaries
          .filter(zoneSummary => zoneSummary.totalRecords > 0)
          .map(zoneSummary => zoneSummary.zoneId)
      );

      this.zoneOptions = this.zoneOptions.map(zoneOption => ({
        ...zoneOption,
        hasExistingRecords: zonesWithRecords.has(zoneOption.value)
      }));

      if (zoneSummaries.length > 0 || this.zoneOptions.length > 0) {
        this.updateZoneStates();
      }
    } catch (e) {
      console.warn('Could not check existing records:', e);
    }
  }

  getZoneIcon(zoneName, index) {
    // Try to match by zone name first
    if (this.zoneIcons[zoneName]) {
      return this.zoneIcons[zoneName];
    }
    
    // Fallback to standard icons with variety
    const standardIcons = [
      'standard:location',
      'standard:groups', 
      'standard:places',
      'standard:territory',
      'standard:address',
      'standard:record',
      'standard:portal_roles',
      'standard:people'
    ];
    
    return standardIcons[index % standardIcons.length];
  }

  updateZoneStates() {
    this.zoneOptions = this.zoneOptions.map(zone => ({
      ...zone,
      tileClass: this.getZoneTileClass(zone),
      iconVariant: zone.selected ? 'brand' : 'default',
      disabled: false
    }));
    this.calculateExpectedRecords();
    this.checkShowGenerateSection();
  }

  getZoneTileClass(zone) {
    const classes = ['zone-tile'];

    if (zone.hasExistingRecords) {
      classes.push('zone-tile-has-records');
    }

    if (zone.selected) {
      classes.push('zone-tile-selected');
    }

    return classes.join(' ');
  }

  resetPreviewState() {
    this.rows = [];
    this.counts = { create: 0, update: 0, skip: 0 };
    this.draftValues = [];
    this.selectedKeys = new Set();
    this.hasPreviewEdits = false;
    this.zoneFilter = 'ALL';
    this.expandedZones = new Set();
    this.zoneSummaries = [];
    this.showPlaceholderSection = false;
    this.selectedZoneId = '';
    this.selectedMode = '';
    this.selectedSlots = '';
    this.dateOptions = [];
    this.selectedDateIds = [];
    this.selectedUniqueDates = [];
    this.selectedPlaceholderScheduleIds = [];
    this.lastGeneratedSummary = '';
    this.calculateExpectedRecords();
  }

  handleYearOption(e) {
    const val = e.detail.value;
    this.yearOption = val;
    this.resetPreviewState();
    if (val === 'CUSTOM') {
      this.showCustomYear = true;
      // keep existing customYear value if present; otherwise, suggest current value
      this.customYear = this.customYear && /^\d{4}$/.test(this.customYear) ? this.customYear : String(this.year);
      this.yearBanner = '';
      this.recomputeDisableGenerate();
    } else {
      this.showCustomYear = false;
      this.customYear = '';
      this.year = Number.parseInt(val, 10);
      // Ensure preset year exists as a record too
      this.busy = true;
      this.recomputeDisableGenerate();
      ensureScheduleYear({ year: this.year })
        .then(() => {
          this.refreshYearBanner();
          // Check existing records when year changes
          if (this.zoneOptions.length > 0) {
            this.checkExistingRecords();
          }
        })
        .catch(err => this.toast(this.err(err), 'error'))
        .finally(() => { this.busy = false; this.recomputeDisableGenerate(); });
    }
  }

  async handleCustomYear(e) {
    const entered = (e.target.value || '').trim();
    this.customYear = entered;
    this.resetPreviewState();
    // validate 4-digit
    if (!/^\d{4}$/.test(entered)) {
      this.toast('Enter a valid 4-digit year, e.g., 2025', 'error');
      this.recomputeDisableGenerate();
      return;
    }
    const yrNum = Number.parseInt(entered, 10);
    this.busy = true;
    this.recomputeDisableGenerate();
    try {
      // Ensure record exists; if not, create with Planned status
      await ensureScheduleYear({ year: yrNum });
      this.year = yrNum;
      await this.refreshYearBanner();
      if (this.zoneOptions.length > 0) {
        await this.checkExistingRecords();
      }
    } catch (error_) {
      this.toast(this.err(error_), 'error');
    } finally {
      this.busy = false;
      this.recomputeDisableGenerate();
    }
  }

  // Zone selection handlers
  handleZoneTileClick(e) {
    e.preventDefault();
    e.stopPropagation();
    const zoneId = e.currentTarget.dataset.zoneId;
    // Allow toggling even if the zone has existing records; preview will classify actions
    this.toggleZoneSelection(zoneId);
  }

  handleZoneCheckboxChange(e) {
    e.stopPropagation();
    const zoneId = e.target.dataset.zoneId;
    this.toggleZoneSelection(zoneId);
  }

  toggleZoneSelection(zoneId) {
    const currentZone = this.zoneOptions.find(zone => zone.value === zoneId);
    if (!currentZone) return; // allow toggling regardless of existing records

    const newSelected = !currentZone.selected;
    // Update the zone options
    this.zoneOptions = this.zoneOptions.map(option => {
      if (option.value === zoneId) {
        return { ...option, selected: newSelected };
      }
      return option;
    });
    // Update selectedZones array
    if (newSelected) {
      this.selectedZones = [...this.selectedZones, zoneId];
    } else {
      this.selectedZones = this.selectedZones.filter(id => id !== zoneId);
    }
    this.updateZoneStates();
    this.recomputeDisableGenerate();
    
    // Clear preview if no zones selected
    if (this.selectedZones.length === 0) {
      this.resetPreviewState();
    }
  }

  selectAllZones() {
    // Select all zones including those with existing records; actions will be determined by preview
    this.zoneOptions = this.zoneOptions.map(zone => ({ 
      ...zone, 
      selected: true 
    }));
    this.selectedZones = this.zoneOptions.filter(zone => zone.selected).map(zone => zone.value);
    this.updateZoneStates();
    this.recomputeDisableGenerate();
    // Don't automatically refresh preview - wait for user to click Generate
    this.resetPreviewState();
  }

  clearAllZones() {
    // Clear all selections regardless of existing records status
    this.zoneOptions = this.zoneOptions.map(zone => ({ 
      ...zone, 
      selected: false 
    }));
    this.selectedZones = this.zoneOptions.filter(zone => zone.selected).map(zone => zone.value);
    this.updateZoneStates();
    this.recomputeDisableGenerate();
    // Auto-refresh preview or clear it
    if (this.selectedZones.length > 0) {
      this.onPreview();
    } else {
      this.resetPreviewState();
    }
  }

  // Removed handleAction (no UI control calls it)

  // Zone expansion handlers
  toggleZoneExpansion(e) {
    const zoneName = e.currentTarget.dataset.zoneName;
    if (this.expandedZones.has(zoneName)) {
      this.expandedZones.delete(zoneName);
    } else {
      this.expandedZones.add(zoneName);
    }
    // Force reactivity
    this.expandedZones = new Set(this.expandedZones);
  }

  expandAllZones() {
    const allZoneNames = this.groupedByZone.map(group => group.zoneName);
    this.expandedZones = new Set(allZoneNames);
  }

  collapseAllZones() {
    this.expandedZones = new Set();
  }
  
  toggleCompactView() {
    // Toggle the compact view flag
    this.showCompactLayout = !this.showCompactLayout;
    
    // This functionality is now less important as we're always showing unique dates
    // but keeping it for potential future enhancements
    this.dispatchEvent(
      new ShowToastEvent({
        title: 'View Changed',
        message: this.showCompactLayout ? 'Showing unique dates per zone' : 'Standard view',
        variant: 'success'
      })
    );
  }
  
  toggleDebugView() {
    this.debugView = !this.debugView;
  }

  getRowSelectionKey(row) {
    if (!row?.zoneId || !row?.calculatedDate) {
      return null;
    }

    return `${row.zoneId}|${row.calculatedDate}`;
  }

  buildZoneDateKey(zoneId, interviewDate) {
    if (!zoneId || !interviewDate) {
      return null;
    }

    return `${zoneId}|${interviewDate}`;
  }

  summarizeUniqueDateAction(rowsForDate) {
    if (!rowsForDate?.length) {
      return '';
    }

    const hasCreate = rowsForDate.some(row => row.action === 'CREATE');
    const hasUpdate = rowsForDate.some(row => row.action === 'UPDATE');
    const hasSkip = rowsForDate.some(row => row.action === 'SKIP');

    if (hasSkip && !hasCreate && !hasUpdate) {
      return 'SKIP';
    }

    if (hasUpdate && !hasCreate) {
      return 'UPDATE';
    }

    if (hasCreate && !hasUpdate && !hasSkip) {
      return 'CREATE';
    }

    if (hasCreate && hasUpdate) {
      return 'UPDATE';
    }

    if (hasCreate) {
      return 'CREATE';
    }

    if (hasUpdate) {
      return 'UPDATE';
    }

    return 'SKIP';
  }

  getDeleteStatusInfo(hasExistingRecords, isPublished, hasBookedPlaceholderRows) {
    if (hasBookedPlaceholderRows) {
      return {
        label: 'Locked — Booked placeholders',
        className: 'slds-text-color_error'
      };
    }

    if (isPublished) {
      return {
        label: 'Locked — Published',
        className: 'slds-text-color_weak'
      };
    }

    if (hasExistingRecords) {
      return {
        label: 'Delete eligible',
        className: 'slds-text-color_success'
      };
    }

    return {
      label: 'Not applicable yet',
      className: 'slds-text-color_weak'
    };
  }

  applyPreviewRows(data) {
    const decorated = (data || []).map((r, i) => ({
      id: i,
      ...r,
      rule: buildRuleText(r.ordinal, r.dow, r.month),
      actionClass: getActionClass(r.action)
    }));

    this.rows = decorated;
    this.selectedKeys = new Set();
    this.hasPreviewEdits = false;
    this.zoneFilter = 'ALL';

    let c = 0;
    let u = 0;
    let s = 0;
    decorated.forEach(r => {
      if (r.action === 'CREATE') c++;
      else if (r.action === 'UPDATE') u++;
      else s++;
    });
    this.counts = { create: c, update: u, skip: s };
    this.calculateExpectedRecords();
    this.createZoneSummaries();
    this.showPlaceholderSection = decorated.length > 0;
  }

  async refreshPreviewRows() {
    if (!this.selectedZones || this.selectedZones.length === 0) {
      this.resetPreviewState();
      return;
    }

    const data = await previewScheduleDates({ year: this.year, zoneIds: this.selectedZones });
    this.applyPreviewRows(data);
  }

  handleRowSelection(e) {
    const zoneName = e.currentTarget?.dataset?.zoneName || e.target?.dataset?.zoneName;
    const selected = e.detail.selectedRows || [];
    const nextKeys = new Set(this.selectedKeys);

    if (zoneName) {
      const currentZone = this.groupedByZone.find(group => group.zoneName === zoneName);
      (currentZone?.items || []).forEach(row => nextKeys.delete(row.selectionKey));
    } else {
      nextKeys.clear();
    }

    selected.forEach(row => {
      if (row.selectionKey) {
        nextKeys.add(row.selectionKey);
      }
    });
    this.selectedKeys = nextKeys;
    // Recompute expected count based on selected preview rows
    this.calculateExpectedRecords();
  }

  handleSave(e) {
    // e.detail.draftValues includes items like { id: 3, calculatedDate: '2025-05-12' }
    const drafts = e.detail.draftValues || [];
    // Basic validation: year must match selected year
    const invalid = drafts.find(d => d.calculatedDate && !String(d.calculatedDate).startsWith(String(this.year)));
    if (invalid) {
      this.toast(`Edited date must be within ${this.year}`, 'error');
      return;
    }
    // Merge drafts into rows
    const byId = new Map(this.rows.map(r => [r.id, { ...r }]));
    const displayRowSelectionKeyById = new Map(
      this.groupedByZone
        .flatMap(group => group.items)
        .map(row => [row.id, row.selectionKey])
    );
    drafts.forEach(d => {
      const selectionKey = displayRowSelectionKeyById.get(d.id);
      if (!selectionKey || !d.calculatedDate) {
        return;
      }

      this.rows
        .filter(row => this.getRowSelectionKey(row) === selectionKey)
        .forEach(row => {
          const current = byId.get(row.id);
          if (current) {
            current.calculatedDate = d.calculatedDate;
          }
        });
    });
    this.rows = Array.from(byId.values());
    this.draftValues = [];
    this.hasPreviewEdits = true;
  }

  async onPreview() {
    // Validate custom year before proceeding
    if (this.showCustomYear) {
      if (!/^\d{4}$/.test(this.customYear || '')) {
        this.toast('Enter a valid 4-digit year, e.g., 2025', 'error');
        return;
      }
      this.year = Number.parseInt(this.customYear, 10);
    }
    this.busy = true;
    this.recomputeDisableGenerate();
    try {
      await this.refreshPreviewRows();
    } catch (e) {
      this.toast(this.err(e), 'error');
    } finally {
      this.busy = false;
      this.recomputeDisableGenerate();
    }
  }

  async onGenerate() {
    // Validate custom year before proceeding
    if (this.showCustomYear) {
      if (!/^\d{4}$/.test(this.customYear || '')) {
        this.toast('Enter a valid 4-digit year, e.g., 2025', 'error');
        return;
      }
      this.year = Number.parseInt(this.customYear, 10);
    }
    this.busy = true;
    this.recomputeDisableGenerate();
    try {
      const selectedRows = this.rows.filter(row => (
        this.selectedKeys.size === 0 || this.selectedKeys.has(this.getRowSelectionKey(row))
      ));
      const overrides = selectedRows.map(r => ({
        zoneId: r.zoneId,
        zoneCodeId: r.zoneCodeId,
        ruleId: r.ruleId,
        mode: r.mode,
        calculatedDate: r.calculatedDate,
        exists: r.exists,
        isPublished: r.isPublished,
        action: r.action
      }));

      const useOverrides = this.hasPreviewEdits || this.selectedKeys.size > 0;
      const res = useOverrides
        ? await generateWithOverrides({ year: this.year, action: this.action, overrides })
        : await generate({ year: this.year, zoneIds: this.selectedZones, action: this.action });
      
      this.toast(`Created ${res.createdCount}, Updated ${res.updatedCount}, Skipped ${res.skippedPublished}`, 'success');
      
      await this.refreshPreviewRows();
      await this.refreshYearBanner();
      await this.checkExistingRecords();
      
      // Clear any previous placeholder selections
      this.selectedZoneId = '';
      this.selectedMode = '';
      this.selectedSlots = '';
      this.selectedDateIds = [];
      this.selectedUniqueDates = [];
      this.hasPreviewEdits = false;
    } catch (e) {
      this.toast(this.err(e), 'error');
    } finally {
      this.busy = false;
      this.recomputeDisableGenerate();
    }
  }

  // (Removed) updateGeneratedDatesPreview - not used by template

  // These methods have been moved to dateUtils.js

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title: 'Generate Interview Dates', message, variant }));
  }
  err(e){ return e?.body?.message || e?.message || 'Unknown error'; }

  // Utility: format a yyyy-mm-dd string as "Wed Oct 3, 2025"
  formatDateLabel(dateStr) {
    const date = new Date(`${dateStr}T00:00:00Z`);
    if (Number.isNaN(date.getTime())) {
      return dateStr;
    }

    return new Intl.DateTimeFormat('en-US', {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      timeZone: 'UTC'
    }).format(date);
  }

  async refreshYearBanner() {
    try {
      const y = this.showCustomYear ? Number.parseInt(this.customYear || '0', 10) : this.year;
      if (!y || Number.isNaN(y)) { this.yearBanner = ''; return; }
      const s = await getScheduleYearSummary({ year: y });
      if (!s?.totalCount) { this.yearBanner = ''; return; }
      const parts = [];
      if (s.publishedCount) parts.push(`${s.publishedCount} Published`);
      if (s.plannedCount) parts.push(`${s.plannedCount} Planned`);
      const msg = parts.length ? parts.join(', ') : `${s.totalCount} existing`;
      this.yearBanner = `This year already has ${msg} schedule record(s).`;
    } catch (error) {
      console.warn('Unable to refresh schedule year banner.', error);
      // Non-blocking
      this.yearBanner = '';
    }
  }

  // Enable Generate when: not busy, valid year selected/entered, and at least one zone selected
  recomputeDisableGenerate() {
    const yearValid = this.isYearValid();
    const hasZones = Array.isArray(this.selectedZones) && this.selectedZones.length > 0;
    this.disableGenerate = !!(this.busy || !yearValid || !hasZones);
    // Allow Delete when not busy and valid year (zones optional)
    this.disableDelete = !!(this.busy || !yearValid);
  }

  isYearValid() {
    let y;
    if (this.showCustomYear) {
      if (!/^\d{4}$/.test(this.customYear || '')) return false;
      y = Number.parseInt(this.customYear, 10);
    } else {
      y = this.year;
    }
    return Number.isInteger(y) && y >= 2000 && y <= 2100;
  }

  // Computed properties for zone selection
  get selectedZoneCount() {
    return this.selectedZones?.length || 0;
  }

  get selectedZoneLabel() {
    return this.selectedZoneCount === 1 ? 'zone' : 'zones';
  }

  get hasExistingRecords() {
    return this.zoneOptions.some(zone => zone.selected && zone.hasExistingRecords);
  }

  get hasSelectedZonesWithExistingRecords() {
    return this.selectedZones.some(zoneId => {
      const zone = this.zoneOptions.find(z => z.value === zoneId);
      return zone?.hasExistingRecords === true;
    });
  }

  calculateExpectedRecords() {
    // Prefer using preview data when available: count rows that will CREATE
    if (this.rows && this.rows.length > 0) {
      const scope = this.selectedKeys && this.selectedKeys.size > 0
        ? this.rows.filter(row => this.selectedKeys.has(this.getRowSelectionKey(row)))
        : this.rows;
      this.expectedRecordCount = scope.filter(r => r.action === 'CREATE').length;
      return;
    }

    // Otherwise estimate using selected zones that do NOT have existing records
    const selectableZoneIds = (this.selectedZones || []).filter(zoneId => {
      const z = this.zoneOptions.find(zz => zz.value === zoneId);
      return z && !z.hasExistingRecords;
    });
    // Default monthly estimate per zone
    this.expectedRecordCount = selectableZoneIds.length * 12;
  }

  checkShowGenerateSection() {
    // Show generate section whenever zones are selected (even if some have existing records)
    this.showGenerateSection = this.selectedZones.length > 0;
  }

  get noRowsSelected() {
    return this.selectedKeys.size === 0;
  }

  // Computed property for zone-grouped data
  get groupedByZone() {
    const base = this.filteredRows;
    if (!base || base.length === 0) return [];

    const bookedPlaceholderZoneDateKeys = this.bookedPlaceholderZoneDateKeys;

    // Group rows by zone
    const zoneMap = new Map();
    base.forEach(row => {
      const zoneName = row.zoneName;
      if (!zoneMap.has(zoneName)) {
        zoneMap.set(zoneName, []);
      }
      zoneMap.get(zoneName).push(row);
    });

    // Convert to array with metadata
    return Array.from(zoneMap.entries()).map(([zoneName, items]) => {
      // Filter to show only unique dates per zone
      // We'll use a Map to track unique dates by their calculatedDate
      const uniqueDatesMap = new Map();
      const displayItems = [];
      
      items.forEach(item => {
        // Use the calculatedDate (the field used throughout the grid) as the uniqueness key
        const dateKey = item.calculatedDate;
        if (!uniqueDatesMap.has(dateKey)) {
          uniqueDatesMap.set(dateKey, []);
        }

        uniqueDatesMap.get(dateKey).push(item);
      });

      uniqueDatesMap.forEach(rowsForDate => {
        const firstItem = rowsForDate[0];
        const summarizedAction = this.summarizeUniqueDateAction(rowsForDate);
        const hasExistingRecords = rowsForDate.some(row => row.exists);
        const zoneDateKey = this.buildZoneDateKey(firstItem.zoneId, firstItem.calculatedDate);
        const hasBookedPlaceholderRows = zoneDateKey ? bookedPlaceholderZoneDateKeys.has(zoneDateKey) : false;
        const isPublished = rowsForDate.every(row => row.isPublished === true);
        const hasDeletableRecords = rowsForDate.some(row => row.exists && row.isPublished !== true) && !hasBookedPlaceholderRows;
        const deleteStatusInfo = this.getDeleteStatusInfo(hasExistingRecords, isPublished, hasBookedPlaceholderRows);

        displayItems.push({
          ...firstItem,
          selectionKey: this.getRowSelectionKey(firstItem),
          action: summarizedAction,
          actionClass: getActionClass(summarizedAction),
          exists: hasExistingRecords,
          isPublished,
          hasBookedPlaceholderRows,
          deleteLockReason: hasBookedPlaceholderRows ? 'Booked placeholder rows exist for this date.' : '',
          deleteStatusLabel: deleteStatusInfo.label,
          deleteStatusClass: deleteStatusInfo.className,
          hasDeletableRecords,
          sourceRowCount: rowsForDate.length
        });
      });
      
      // Count action types based on unique dates
      const createCount = displayItems.filter(item => item.action === 'CREATE').length;
      const updateCount = displayItems.filter(item => item.action === 'UPDATE').length;
      const skipCount = displayItems.filter(item => item.action === 'SKIP').length;
      const lockedCount = displayItems.filter(item => item.hasBookedPlaceholderRows === true).length;
      
      return {
        zoneName,
        items: displayItems, // Show only unique dates for each zone
        allItems: items, // Keep all items for reference/processing
        selectedRowIds: displayItems
          .filter(item => this.selectedKeys.has(item.selectionKey))
          .map(item => item.id),
        itemCount: displayItems.length, // Count of unique dates displayed
        totalRecordsCount: items.length, // Total records before filtering
        createCount,
        updateCount,
        skipCount,
        lockedCount,
        isExpanded: this.expandedZones.has(zoneName),
        expandIcon: this.expandedZones.has(zoneName) ? 'utility:chevrondown' : 'utility:chevronright'
      };
    }).sort((a, b) => a.zoneName.localeCompare(b.zoneName));
  }

  // Modal-related computed properties
  get hasSelectedZones() {
    return this.selectedZones && this.selectedZones.length > 0;
  }

  get selectedZoneNames() {
    if (!this.hasSelectedZones) return '';
    const selectedOptions = this.zoneOptions.filter(opt => this.selectedZones.includes(opt.value));
    return selectedOptions.map(opt => opt.label).join(', ');
  }

  get disableDeleteConfirm() {
    return this.deleteConfirmationText !== 'DELETE';
  }

  get selectedPreviewRows() {
    if (!this.selectedKeys || this.selectedKeys.size === 0) {
      return [];
    }

    return this.groupedByZone
      .flatMap(group => group.items)
      .filter(row => this.selectedKeys.has(row.selectionKey));
  }

  get selectedSourceRows() {
    if (!this.selectedKeys || this.selectedKeys.size === 0) {
      return [];
    }

    return this.rows.filter(row => this.selectedKeys.has(this.getRowSelectionKey(row)));
  }

  get deletableSelectedSourceRows() {
    const lockedSelectionKeys = new Set(this.deleteLockedSelectedRows.map(row => row.selectionKey));

    return this.selectedSourceRows.filter(row => (
      row.exists
      && row.isPublished !== true
      && !lockedSelectionKeys.has(this.getRowSelectionKey(row))
    ));
  }

  get deletableSelectedRows() {
    return this.selectedPreviewRows.filter(
      row => row.hasDeletableRecords === true && row.hasBookedPlaceholderRows !== true
    );
  }

  get deleteLockedSelectedRows() {
    return this.selectedPreviewRows.filter(row => row.hasBookedPlaceholderRows === true);
  }

  get showDeleteSelectedButton() {
    return this.deletableSelectedRows.length > 0;
  }

  get deleteSelectionCount() {
    return this.deletableSelectedRows.length;
  }

  get deleteSelectionLabel() {
    return this.deleteSelectionCount === 1 ? 'unique date' : 'unique dates';
  }

  get deleteSelectionRecordCount() {
    if (!this.deletableSelectedRows.length || !this.rows.length) {
      return 0;
    }

    const selectedZoneDateKeys = new Set(
      this.deletableSelectedRows
        .filter(row => row.zoneId && row.calculatedDate)
        .map(row => `${row.zoneId}|${row.calculatedDate}`)
    );

    return this.rows.filter(row => (
      row.exists
      && row.isPublished !== true
      && selectedZoneDateKeys.has(`${row.zoneId}|${row.calculatedDate}`)
    )).length;
  }

  get deleteSelectionRecordLabel() {
    return this.deleteSelectionRecordCount === 1 ? 'schedule record' : 'schedule records';
  }

  get deleteSelectionZoneNames() {
    const zoneNames = Array.from(new Set(this.deletableSelectedRows.map(row => row.zoneName).filter(Boolean)));
    return zoneNames.join(', ');
  }

  get deleteLockedSelectionCount() {
    return this.deleteLockedSelectedRows.length;
  }

  get deleteLockedSelectionLabel() {
    return this.deleteLockedSelectionCount === 1 ? 'unique date is' : 'unique dates are';
  }

  get previewLockedRows() {
    return this.groupedByZone.flatMap(group => group.items).filter(row => row.hasBookedPlaceholderRows === true);
  }

  get previewLockedDateCount() {
    return this.previewLockedRows.length;
  }

  get previewLockedZoneNames() {
    return Array.from(new Set(this.previewLockedRows.map(row => row.zoneName).filter(Boolean))).join(', ');
  }

  onDeleteAll() {
    // Validate year first
    if (!this.isYearValid()) {
      this.toast('Select a valid year first', 'error');
      return;
    }

    if (!this.showDeleteSelectedButton) {
      this.toast('Select one or more unique dates from the schedule preview to delete.', 'warning');
      return;
    }
    
    // Show the confirmation modal
    this.showDeleteModal = true;
    this.deleteConfirmationText = '';
  }

  closeDeleteModal() {
    this.showDeleteModal = false;
    this.deleteConfirmationText = '';
  }

  handleDeleteConfirmationChange(event) {
    this.deleteConfirmationText = event.target.value;
  }

  async confirmDeleteAll() {
    if (this.deleteConfirmationText !== 'DELETE') {
      return;
    }

    const selectedUniqueDateCount = this.deleteSelectionCount;
    const lockedSelectionCount = this.deleteLockedSelectionCount;

    // Close modal first
    this.closeDeleteModal();

    this.busy = true;
    this.recomputeDisableGenerate();
    try {
      const overrides = this.deletableSelectedSourceRows.map(row => ({
        zoneId: row.zoneId,
        zoneCodeId: row.zoneCodeId,
        ruleId: row.ruleId,
        mode: row.mode,
        calculatedDate: row.calculatedDate,
        exists: row.exists,
        isPublished: row.isPublished,
        action: row.action
      }));

      const res = await deleteScheduleDatesWithOverrides({ year: this.year, overrides });
      const uniqueDateLabel = selectedUniqueDateCount === 1 ? 'unique date' : 'unique dates';
      let message = `Deleted ${res.deletedCount} schedule record(s) across ${selectedUniqueDateCount} selected ${uniqueDateLabel}.`;
      if (lockedSelectionCount > 0) {
        message += ` ${lockedSelectionCount} selected ${lockedSelectionCount === 1 ? 'date was' : 'dates were'} skipped because booked placeholder rows already exist.`;
      }
      this.toast(message, 'success');
      await this.refreshYearBanner();
      await this.checkExistingRecords();
      await this.refreshPreviewRows();
    } catch (e) {
      this.toast(this.err(e), 'error');
    } finally {
      this.busy = false;
      this.recomputeDisableGenerate();
    }
  }

  // Filter rows by selected zone name (for debug and grouped views)
  get filteredRows() {
    if (!this.rows || this.rows.length === 0) return [];
    if (this.zoneFilter === 'ALL') return this.rows;
    return this.rows.filter(r => r.zoneName === this.zoneFilter);
  }

  // Zone filter options sourced from the current rows
  get zoneFilterOptions() {
    const zoneNames = Array.from(
      new Set((this.rows || []).map(row => row.zoneName).filter(Boolean))
    ).sort((left, right) => left.localeCompare(right));

    return [
      { label: 'All Zones', value: 'ALL' },
      ...zoneNames.map(zoneName => ({ label: zoneName, value: zoneName }))
    ];
  }

  handleZoneFilterChange(e) {
    this.zoneFilter = e.detail.value;
  }

  handleDebugToggle(e) {
    this.debugView = e.target.checked;
  }

  handleDisplayMenuSelect(event) {
    const action = event.detail.value;
    if (action === 'toggleCompactView') {
      this.toggleCompactView();
      return;
    }

    if (action === 'debugView') {
      this.toggleDebugView();
    }
  }

  // Rows for debug table
  get debugRows() {
    return this.filteredRows.map(r => ({ id: r.id, rule: r.rule, calculatedDate: r.calculatedDate }));
  }
  
  // ========= PLACEHOLDER GENERATION METHODS =========
  // Handle selecting a zone for placeholder generation
  handlePlaceholderZoneChange(e) {
    this.selectedZoneId = e.detail.value;
    this.selectedDateIds = [];
    this.selectedUniqueDates = [];
    this.selectedMode = '';
    this.selectedSlots = '';
    this.selectedPlaceholderScheduleIds = [];
    this.loadDatesForZone();
  }

  getInterviewDaySchedules(interviewDay) {
    const relationship = interviewDay?.Interview_Day_Schedules__r;
    if (!relationship) {
      return [];
    }

    if (Array.isArray(relationship)) {
      return relationship;
    }

    if (Array.isArray(relationship.records)) {
      return relationship.records;
    }

    return [];
  }

  get activePlaceholderYear() {
    if (this.showCustomYear) {
      if (!/^\d{4}$/.test(this.customYear || '')) {
        return null;
      }
      return Number.parseInt(this.customYear, 10);
    }

    return this.year;
  }

  buildPlaceholderRows(limitToSelectedZone = true) {
    const interviewDays = this.wiredExistingInterviewDays?.data || [];
    const activeYear = this.activePlaceholderYear;

    return interviewDays
      .filter(interviewDay => {
        if (activeYear && interviewDay?.Year__c !== activeYear) {
          return false;
        }

        if (limitToSelectedZone && this.selectedZoneId && interviewDay?.Zone__c !== this.selectedZoneId) {
          return false;
        }

        return true;
      })
      .flatMap(interviewDay => {
        const zoneName = interviewDay?.Zone__r?.Name || 'Unknown Zone';
        const scheduleMode = interviewDay?.Schedule_Mode__c || interviewDay?.Mode__c || '';

        return this.getInterviewDaySchedules(interviewDay).map(schedule => ({
          id: schedule.Id,
          recordId: schedule.Id,
          interviewDayId: interviewDay.Id,
          zoneId: interviewDay.Zone__c,
          zoneName,
          interviewDate: interviewDay.Interview_Date__c,
          scheduleMode,
          scheduleName: schedule.Name,
          booked: schedule.Booked__c === true,
          isDeleteEligible: schedule.Booked__c !== true,
          status: schedule.Status__c || interviewDay.Status__c || ''
        }));
      })
      .sort((left, right) => {
        const leftValue = `${left.interviewDate || ''}|${left.zoneName || ''}|${left.scheduleMode || ''}|${left.scheduleName || ''}`;
        const rightValue = `${right.interviewDate || ''}|${right.zoneName || ''}|${right.scheduleMode || ''}|${right.scheduleName || ''}`;
        return leftValue.localeCompare(rightValue);
      });
  }

  get existingPlaceholderRows() {
    return this.buildPlaceholderRows(true);
  }

  get bookedPlaceholderZoneDateKeys() {
    const keys = new Set();

    this.buildPlaceholderRows(false)
      .filter(row => row.booked === true)
      .forEach(row => {
        const zoneDateKey = this.buildZoneDateKey(row.zoneId, row.interviewDate);
        if (zoneDateKey) {
          keys.add(zoneDateKey);
        }
      });

    return keys;
  }

  get hasExistingPlaceholderRows() {
    return this.existingPlaceholderRows.length > 0;
  }

  get selectedPlaceholderScheduleCount() {
    return this.selectedPlaceholderScheduleIds.length;
  }

  get disabledPlaceholderScheduleIds() {
    return this.existingPlaceholderRows
      .filter(row => row.booked === true)
      .map(row => row.id);
  }

  get selectedPlaceholderScheduleLabel() {
    return this.selectedPlaceholderScheduleCount === 1 ? 'placeholder row' : 'placeholder rows';
  }

  get showDeleteSelectedPlaceholderButton() {
    return this.selectedPlaceholderScheduleCount > 0;
  }

  handleExistingPlaceholderToggle(e) {
    this.showExistingPlaceholderRows = e.target.checked;
    this.selectedPlaceholderScheduleIds = [];
  }

  handleExistingPlaceholderSelection(e) {
    this.selectedPlaceholderScheduleIds = (e.detail.selectedRows || [])
      .filter(row => row.booked !== true)
      .map(row => row.id);
  }

  async handleDeleteSelectedPlaceholders() {
    if (!this.selectedPlaceholderScheduleIds.length) {
      this.toast('Select one or more placeholder rows to delete.', 'warning');
      return;
    }

    this.busy = true;
    this.recomputeDisableGenerate();
    try {
      const res = await deleteSelectedInterviewSchedules({ scheduleIds: this.selectedPlaceholderScheduleIds });
      const parts = [`Deleted ${res.deletedScheduleCount} placeholder row(s)`];
      if (res.skippedBookedCount) {
        parts.push(`Skipped ${res.skippedBookedCount} booked row(s)`);
      }
      if (res.deletedInterviewDayCount) {
        parts.push(`Removed ${res.deletedInterviewDayCount} empty interview day record(s)`);
      }

      this.toast(parts.join('. ') + '.', 'success');
      this.selectedPlaceholderScheduleIds = [];
      await refreshApex(this.wiredExistingInterviewDays);
      await this.refreshYearBanner();
      await this.checkExistingRecords();
      await this.refreshPreviewRows();
    } catch (error) {
      this.toast(this.err(error), 'error');
    } finally {
      this.busy = false;
      this.recomputeDisableGenerate();
    }
  }

  // Load available dates for the selected zone
  async loadDatesForZone() {
    if (!this.selectedZoneId) return;
    
    this.busy = true;
    try {
      const scheduleDates = await getScheduleDatesForZone({ 
        zoneId: this.selectedZoneId, 
        year: this.year 
      });
      
      // Clear existing
      this.dateOptions = [];

      // Deduplicate by Calculated_Date__c so we only show one entry per unique date
      const uniqueByDate = new Map(); // key: YYYY-MM-DD, value: { id, label }
      (scheduleDates || []).forEach(sd => {
        if (!sd?.Calculated_Date__c) return;
        const dateKey = sd.Calculated_Date__c; // Date field is already YYYY-MM-DD
        const label = this.formatDateLabel(sd.Calculated_Date__c);

        if (!uniqueByDate.has(dateKey)) {
          uniqueByDate.set(dateKey, { id: sd.Id, label });
        }
      });

      // Build options array and modes map keyed by the chosen id per date
      const options = [];
      uniqueByDate.forEach((entry) => {
        const { id, label } = entry;
        options.push({
          label,
          value: id,
          isSelected: false,
          pillClass: 'date-pill'
        });
      });

      // Sort options by date label locale if needed (data already ordered by SOQL)
      this.dateOptions = options;
    } catch (error) {
      this.toast(this.err(error), 'error');
    } finally {
      this.busy = false;
    }
  }

  // Handle date selection
  handleDateCardClick(e) {
    const dateId = e.currentTarget.dataset.date;
    const index = this.dateOptions.findIndex(opt => opt.value === dateId);
    
    if (index >= 0) {
      const options = [...this.dateOptions];
      const isSelected = !options[index].isSelected;
      options[index] = {
        ...options[index],
        isSelected,
        pillClass: isSelected ? 'date-pill date-pill-selected' : 'date-pill'
      };
      this.dateOptions = options;
      
      // Update selected dates
      this.selectedDateIds = this.dateOptions
        .filter(opt => opt.isSelected)
        .map(opt => opt.value);
          
      this.selectedUniqueDates = [...this.selectedDateIds];
    }
  }

  // Keyboard support for date pill selection (Enter/Space)
  handleDateCardKeydown(e) {
    const key = e.key || e.code;
    if (key === 'Enter' || key === ' ' || key === 'Spacebar') {
      e.preventDefault();
      this.handleDateCardClick(e);
    }
  }

  // Handle dual listbox date selection for many dates
  handleDateListboxChange(e) {
    this.selectedUniqueDates = e.detail.value;
    this.selectedDateIds = [...this.selectedUniqueDates];
    
    // Update dateOptions to reflect the selection
    this.dateOptions = this.dateOptions.map(opt => ({
      ...opt,
      isSelected: this.selectedDateIds.includes(opt.value),
      pillClass: this.selectedDateIds.includes(opt.value) ? 'date-pill date-pill-selected' : 'date-pill'
    }));
  }

  // Handle mode selection
  handleModeChange(e) {
    this.selectedMode = e.detail.value;
  }

  // Handle slots selection
  handleSlotsChange(e) {
    this.selectedSlots = e.detail.value;
  }

  // Process placeholders
  async handleProcessPlaceholders() {
    if (!this.selectedZoneId || !this.selectedMode || !this.selectedSlots || this.selectedDateIds.length === 0) {
      this.toast('Please complete all fields before processing', 'warning');
      return;
    }
    
    this.busy = true;
    try {
      const slots = Number.parseInt(this.selectedSlots, 10);
      // Normalize UI value to match Apex picklist where Afternoon is stored as AfterNoon
      const apexMode = this.selectedMode === 'Afternoon' ? 'AfterNoon' : this.selectedMode;
      const responseMessage = await processPlaceholdersByDates({
        zoneId: this.selectedZoneId,
        scheduleDateIds: this.selectedDateIds,
        mode: apexMode,
        totalSlots: slots
      });
      const summaryMessage = (responseMessage || 'Interview placeholders processed successfully.').split('\n')[0];

      this.lastGeneratedSummary = summaryMessage;
      this.toast(summaryMessage, 'success');
      
      // Refresh the existing interview days data
      await refreshApex(this.wiredExistingInterviewDays);
      await this.refreshYearBanner();
      await this.checkExistingRecords();
      if (this.selectedZones?.length) {
        await this.refreshPreviewRows();
      }
      
      // Clear selections
      this.selectedDateIds = [];
      this.selectedUniqueDates = [];
      this.selectedMode = '';
      this.selectedSlots = '';
      
      // Update the date options to reflect cleared selection
      this.dateOptions = this.dateOptions.map(opt => ({
        ...opt,
        isSelected: false,
        pillClass: 'date-pill'
      }));
    } catch (error) {
      this.toast(this.err(error), 'error');
    } finally {
      this.busy = false;
    }
  }
  
  // After successful generation, create summary by zone
  handleTabChange(event) {
    const tabValue = event.currentTarget.dataset.tabValue;
    this.currentTab = tabValue;
    
    // If switching to placeholder tab, trigger data load if we have generated dates
    if (tabValue === 'placeholders' && this.rows && this.rows.length > 0) {
      this.createZoneSummaries();
    }
  }

  createZoneSummaries() {
    if (!this.rows || this.rows.length === 0) {
      this.zoneSummaries = [];
      return;
    }

    // Group rows by zone
    const zoneMap = new Map();
    this.rows.forEach(row => {
      const zoneId = row.zoneId;
      const zoneName = row.zoneName;
      
      if (!zoneMap.has(zoneId)) {
        zoneMap.set(zoneId, {
          id: zoneId,
          name: zoneName,
          totalRecords: 0,
          createCount: 0,
          updateCount: 0,
          skipCount: 0,
          dates: new Set()
        });
      }
      
      const zoneSummary = zoneMap.get(zoneId);
      zoneSummary.totalRecords++;
      zoneSummary.dates.add(row.calculatedDate);
      
      if (row.action === 'CREATE') zoneSummary.createCount++;
      else if (row.action === 'UPDATE') zoneSummary.updateCount++;
      else zoneSummary.skipCount++;
    });
    
    // Convert to array and add additional properties
    this.zoneSummaries = Array.from(zoneMap.values()).map(zone => ({
      id: zone.id,
      name: zone.name,
      totalRecords: zone.totalRecords,
      createCount: zone.createCount,
      updateCount: zone.updateCount,
      skipCount: zone.skipCount,
      uniqueDateCount: zone.dates.size,
      iconName: this.getZoneIcon(zone.name, 0)
    }));
    
    // Enable placeholder section after successful generation
    this.showPlaceholderSection = true;
  }
  
  // ========= ADDITIONAL GETTERS FOR PLACEHOLDER FUNCTIONALITY =========
  get slotsOptions() {
    if (!this.selectedMode) return [];

    // Always show 10 to 20 as values regardless of mode
    const options = [];
    for (let i = 10; i <= 20; i++) {
      options.push({ label: `${i} slots`, value: String(i) });
    }
    return options;
  }
  
  get modeOptions() {
    return [
      // Values must align with Interview_Day__c.Schedule_Mode__c picklist
      { label: 'AM Morning (8:00 - 12:00)', value: 'Morning' },
      { label: 'PM Afternoon (12:30 - 4:30)', value: 'Afternoon' }
    ];
  }
  
  get placeholderZoneOptions() {
    if (!this.zoneSummaries || this.zoneSummaries.length === 0) {
      return [];
    }
    
    return this.zoneSummaries.map(zone => ({
      label: zone.name,
      value: zone.id
    }));
  }
  
  get isProcessDisabled() {
    return this.busy || !this.selectedZoneId || !this.selectedMode || 
           !this.selectedSlots || this.selectedDateIds.length === 0;
  }
  
  get totalRecordsToGenerate() {
    if (this.selectedDateIds.length === 0 || !this.selectedSlots) {
      return 0;
    }
    return this.selectedDateIds.length * Number.parseInt(this.selectedSlots, 10);
  }
  
  get shouldShowDateCards() {
    return this.dateOptions.length <= 20; // Show cards for 20 or fewer dates
  }
  
  get dateOptionsForListbox() {
    // Already deduped in loadDatesForZone; expose directly to listbox
    return this.dateOptions.map(date => ({ label: date.label, value: date.value }));
  }
  
  // ========= PLACEHOLDER TAB METHODS =========
  // Note: Duplicate placeholder methods removed. Earlier implementations remain in effect.

  // ========= VIEW/STATE GETTERS USED BY TEMPLATE =========
  get isShowingDatesTab() {
    return this.currentTab === 'dates';
  }

  get isShowingPlaceholdersTab() {
    return this.currentTab === 'placeholders';
  }

  get datesTabClass() {
    return `slds-tabs_default__link${this.isShowingDatesTab ? ' slds-is-active' : ''}`;
  }

  get placeholdersTabClass() {
    return `slds-tabs_default__link${this.isShowingPlaceholdersTab ? ' slds-is-active' : ''}`;
  }

  get datesTabIndex() {
    return this.isShowingDatesTab ? '0' : '-1';
  }

  get placeholdersTabIndex() {
    return this.isShowingPlaceholdersTab ? '0' : '-1';
  }

  get showEmptyPlaceholdersState() {
    return !this.showPlaceholderSection;
  }

  get selectedZoneSummary() {
    if (!this.selectedZoneId) return null;
    return this.zoneSummaries.find(z => z.id === this.selectedZoneId) || null;
  }

  get selectedZoneDateCount() {
    return this.selectedZoneSummary ? this.selectedZoneSummary.uniqueDateCount : 0;
  }
}