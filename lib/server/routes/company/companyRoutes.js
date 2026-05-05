const express = require('express');
const router = express.Router();
const mysql = require('mysql2/promise');
const multer = require('multer');

// DB Connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

// Get all companies
router.get('/', async (req, res) => {
  try {
    const [companies] = await pool.execute(
      `SELECT c.*, COUNT(b.branch_id) as branch_count 
       FROM companies c 
       LEFT JOIN branches b ON c.company_id = b.company_id 
       GROUP BY c.company_id 
       ORDER BY c.company_name`
    );
    res.json({ success: true, data: companies });
  } catch (error) {
    console.error('Error fetching companies:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch companies' });
  }
});

// Create new company
router.post('/', async (req, res) => {
  try {
    const { company_name } = req.body;
    
    if (!company_name) {
      return res.status(400).json({ success: false, message: 'Company name is required' });
    }

    const [result] = await pool.execute(
      'INSERT INTO companies (company_name) VALUES (?)',
      [company_name]
    );

    res.json({ 
      success: true, 
      message: 'Company created successfully',
      data: { company_id: result.insertId, company_name }
    });
  } catch (error) {
    console.error('Error creating company:', error);
    res.status(500).json({ success: false, message: 'Failed to create company' });
  }
});

// Update company
router.put('/:company_id', async (req, res) => {
  try {
    const { company_id } = req.params;
    const { company_name } = req.body;
    
    if (!company_name) {
      return res.status(400).json({ success: false, message: 'Company name is required' });
    }

    const [result] = await pool.execute(
      'UPDATE companies SET company_name = ? WHERE company_id = ?',
      [company_name, company_id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Company not found' });
    }

    res.json({ success: true, message: 'Company updated successfully' });
  } catch (error) {
    console.error('Error updating company:', error);
    res.status(500).json({ success: false, message: 'Failed to update company' });
  }
});

// Delete company
router.delete('/:company_id', async (req, res) => {
  try {
    const { company_id } = req.params;
    
    const [result] = await pool.execute(
      'DELETE FROM companies WHERE company_id = ?',
      [company_id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Company not found' });
    }

    res.json({ success: true, message: 'Company deleted successfully' });
  } catch (error) {
    console.error('Error deleting company:', error);
    res.status(500).json({ success: false, message: 'Failed to delete company' });
  }
});

// Get branches for a company
router.get('/:company_id/branches', async (req, res) => {
  try {
    const { company_id } = req.params;
    
    const [branches] = await pool.execute(
      'SELECT * FROM branches WHERE company_id = ? ORDER BY branch_name',
      [company_id]
    );
    
    res.json({ success: true, data: branches });
  } catch (error) {
    console.error('Error fetching branches:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch branches' });
  }
});

// Create new branch
router.post('/:company_id/branches', async (req, res) => {
  try {
    const { company_id } = req.params;
    const { branch_name, city } = req.body;
    
    if (!branch_name) {
      return res.status(400).json({ success: false, message: 'Branch name is required' });
    }

    const [result] = await pool.execute(
      'INSERT INTO branches (company_id, branch_name, city) VALUES (?, ?, ?)',
      [company_id, branch_name, city || null]
    );

    res.json({ 
      success: true, 
      message: 'Branch created successfully',
      data: { branch_id: result.insertId, company_id, branch_name, city }
    });
  } catch (error) {
    console.error('Error creating branch:', error);
    res.status(500).json({ success: false, message: 'Failed to create branch' });
  }
});

// Update branch
router.put('/:company_id/branches/:branch_id', async (req, res) => {
  try {
    const { company_id, branch_id } = req.params;
    const { branch_name, city } = req.body;
    
    if (!branch_name) {
      return res.status(400).json({ success: false, message: 'Branch name is required' });
    }

    const [result] = await pool.execute(
      'UPDATE branches SET branch_name = ?, city = ? WHERE branch_id = ? AND company_id = ?',
      [branch_name, city || null, branch_id, company_id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Branch not found' });
    }

    res.json({ success: true, message: 'Branch updated successfully' });
  } catch (error) {
    console.error('Error updating branch:', error);
    res.status(500).json({ success: false, message: 'Failed to update branch' });
  }
});

// Delete branch
router.delete('/:company_id/branches/:branch_id', async (req, res) => {
  try {
    const { company_id, branch_id } = req.params;
    
    const [result] = await pool.execute(
      'DELETE FROM branches WHERE branch_id = ? AND company_id = ?',
      [branch_id, company_id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Branch not found' });
    }

    res.json({ success: true, message: 'Branch deleted successfully' });
  } catch (error) {
    console.error('Error deleting branch:', error);
    res.status(500).json({ success: false, message: 'Failed to delete branch' });
  }
});

module.exports = router;
